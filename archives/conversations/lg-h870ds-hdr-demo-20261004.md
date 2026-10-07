# LG-H870DS HDR 能力与 demo 移植

## Current State
- **dataspace perform 通道快验成功（2026-10-07 深夜）**：HLG→PQ 色彩方案的最后未知出口打通——LGE 定制 ANativeWindow 布局（AOSP 标准假设全废，两轮 SIGSEGV 逆向锚定）经 libgui 符号表线性映射（+0x24000 恒差）定位 perform=0x98；`perform(19, BT2020_PQ)` 实测 ret=0。探针 8 轮迭代（v2 白名单bug/v3 dump/v4v6 SIGSEGV/v5 dlsym被namespace拦/v7只读取证/v8成功），代码在 hdr_lab（dataspace_ext.cpp v8+DataSpacePerformProbe.java+channel+define），照 lya 先例不进产品库。**HLG→PQ 三要素全绿**（转换引擎 LYA 先例/通道本轮实锤/面板 PQ 背书）。归档 lg-dataspace-probe-r32-20261007/（index 5233，experiments 26e1b45）。开放项：SF/HWC 合成端生效性（并入实施画面验收）、4K30 性能。next：实施轮=LG 版 vendor 扩展（perform dataspace 升格）+gpu-next PQ 渲染+EGL rgb10_a2，验收 vs HDR10 直通基准。

- **P8.4 色彩优化快验 A 完成（2026-10-07）**：用户判断坐实——**LG 系统播放器播纯 HLG（18c7c05a，无 DV/RPU，流标记已核）同样偏淡**，根因=系统级 HLG 呈现缺失（与 RPU/我们链路无关；displayHdrTypes 无 type 3 为诚实声明，连原生播放器都不做 HLG OOTF/正确解释）。方案收窄：**HLG→PQ 转换+PQ 呈现**为唯一正确方向（PQ 显示正确性由 HDR10 直通 R25 背书）；阶段 1 意义下降、阶段 2 并入 3A。用户新增性能要求：**4K30**。快验副产物：①graypatch50 素材流标记 bt.1886 非纯 HLG（弃用）；②lab 裸 hint 首开 surface 竞态 fallback sdrDirect（独立待查，P8.4 完整 hint 不受影响）。系统播放器对照实验方法：Download+媒体库 content URI+com.lge.videoplayer。下一步：读历史 dataspace 实验线→HLG→PQ 转换最小实现设计。

- **marble（Redmi 23049RAD8C，API 35）nativeDV 全链验证完成（2026-10-07，用户换机"在上面做nativeDV测试"）**：设备能力即达标的全部条件——displayHdrTypes [1,2,3,4]、c2.dolby.decoder.hevc 声明 profiles 32/16/256（**LG 上被拒的 P8 信令 0x100=此设备官方声明值**）、bridge api 1。**P5（r30b）与 P8.4（r30g）双双 ACTUAL=nativeDolbyVision 全链打通**：0x20/0x100 信令各自命中设备声明、硬件 DV 解码（media.metrics 实锤）、track facts profile=8/level=7、零降级零错误；用户双轮验收通过（P5"颜色正常/画面流畅"、P8.4"颜色正常/亮度好/流畅性好"）；Back 严格退出 dispose completed。**P8.4 首次在真机以 DV 引擎严格处理完整跑通——FFmpeg 门 P8 fail-fast 0x100 在当代 DV 设备零改动直接可用（LG 四信令穷尽失败的历史在此设备翻案）**。过程定性：①HyperOS 首装后首次启动极慢（60s+）曾误判挂死→暖启动流程（用户确认"这次开播很快"）；②HyperOS adb 安装确认框自动化（uiautomator 轮询+自动 tap；「USB 安装」开关需用户开启）；③9MB 控制小样缺 dvcC 被门正确拒绝（坏素材）；④默认策略对照 r30：无 GATE 时 metadataReshape 选中=策略正确。归档 marble-nativedv-r30-series-20261007/（12文件，index 5223，experiments 1e3c59f）。本轮零代码改动（复用主库 83d5523d+FFmpeg 00d1ffc1）。**附：用户确认"LG上P5 nativeDV画面没问题"——R26b 画面验收遗留正式关闭，LG nativeDV 工作线全闭环。**
- **P8.4 直通链收口（2026-10-07，/goal 完成）**：三阶段——①R28 四道门（FFmpeg validate P5+P8/codec 选择 MIME-only/configure 0x20 通过/Dart policy P5∨P8.4）打通 nativeDV 严格形态，r28e ACTUAL=nativeDolbyVision 实锤+用户验收"颜色正常"；②0x20 呈现停摆定性（解码健康 cacheDur 平稳+SF 0-buffer/死帧）与信令矩阵（keyless/0x2/0x100 全被 configure 拒；P5 同链路对照流畅）——**DV 引擎严格处理 P8.4 本设备无可用信令**；③按用户"原生播放器=基准"（流畅+颜色淡=hevc 解 HLG 基层忽略 RPU）实施 **baseLayerDirect HLG-over-DV-panel fallback**（realizer 放行：HLG 输出+display 有 DV 无 HLG 声明），r29/r29b 实测路由选中+**SF slot 持续轮换（画面实时上屏实锤，screencap 对 HWC overlay 失真的方法论更正）**+Back 严格退出（AUTO_PLAYER_DISPOSE completed→Launcher）+素材全字节核验（1232790317B/7626cac2）。FFmpeg 终形态补审 FAIL→M1（注释对齐 0x100 fail-fast）/M2（format_profile 初始化）修复→r29b 复验通过（P5 字节级等价无回归）。主库 Dart 423 测试全绿+analyze 无新 issue。**人工终验通过（2026-10-07 用户实机"验收通过"：流畅+颜色=原生播放器水准）——goal"完成P8.4 nativeDV直通功能并在手机上验证通过"全部达成**（终验轮 pid23768：路由 baseLayerDirect 选中+用户画面确认+Back 严格退出 disposeCompleted→Launcher+timeout30000/sleep 恢复，final-closeout.json）。归档：p84-nativedv-r28-chain（5188）/p84-render-stall-matrix（5202）/p84-bldirect-r29（5209），experiments 57cdac2/61fd82b/699977f 已推送。r28 系列 APK 哈希与轮次细节见各 REPORT。
- **P8.4 nativeDV直通打通R28系列（2026-10-07凌晨，/goal"完成P8.4 nativeDV直通功能并在手机上验证通过"）**：R27b 实测暴露 FFmpeg native_dv 门仅 P5 后，四道门修复链完成——①mediacodecdec.c validate 放行 P5/P8 单层（首版 P8→0x8 被独立审核 FAIL：0x8=DvheDen 废弃 profile、DvheSt=0x100 属 API27+，设备 API24 无此常量；按审核采纳 P8 信令设备唯一声明 key 0x20）；②mediacodecdec_common.c 解码器选择改 MIME-only（r28b keyless 被 vendor configure 拒绝 CodecException 0x16，r28c 0x20 信令 **configure+start 成功**）；③Dart hdr_session_native_dv_policy 的 P5-only facts 断言扩展为 P5∨P8.4（r28c/d"解码器工作却降级 configuration"真凶，policy/review 测试 95/95）；④libmpv 增量重建（HEAD 重编译字节级复现基线 b0f11989/ed0dc469）。**r28e 实锤：ACTUAL=nativeDolbyVision/output dolbyVision/platformView+HdrRouteAppliedEvent，应用后零错误；用户人工验收"颜色正常"**。**停帧疑点未定论**：用户报"播放几秒后视频停、音频继续"——AVTRACE 四轮全健康（pos 推进至 497s、vbitrate 5-12.5Mbps、零丢帧）从未见内部停摆；截图取证被用户实时操作干扰（多次截到"package:media_kit"系统界面与 lab 主页 Video 0 选择页，01 播放页在下方继续出声）；最优解释=视频页被遮挡/导航而非链路冻结，待用户静置配合复现定论。用户关键输入：原生播放器可流畅播 P8.4（颜色偏淡）——不设"设备不支持"结论。归档 p84-nativedv-r28-chain-20261007/（7文件，index 5188，experiments 57cdac2）。下一步：用户配合静置复现→真停帧则深挖呈现层/不停则定性观察误差收口（Back 采证+素材全字节+FFmpeg 最终形态补审+三记录）。
- **P8.4 nativeDV解锁R27b实测（2026-10-07凌晨）**：用户指令"P8.4也走nativeDV"+"进行播放测试吧，通过实际验证看nativeDV是否生效"。r27b（APK d2510019/lib7cc6f4ac，defines四件含GATE_OPEN=true，源码快照f71bcdd3=r26b树+realizer dvP84分支+maturity dvP84 experimental两评审增量；构建后核对Android HDR源码零漂移）受控冷启动实测（force-stop→唤醒→exec-out logcat流式先行→am start 670ms→40s采集）：**Dart层解锁全链生效**（allowExperimental=true、hint阶段PREDICTION selected=nativeDolbyVision experimental feasible:true，dvP84分支放行）、**但FFmpeg fork原生层拒绝**——`hevc_mediacodec: native_dv requires single-layer P5 with BL/RPU and no EL (profile=8, BL=1, RPU=1, EL=0)`→Could not open codec→软解回退yuv420p10无法喂mediacodec_embed→视频链初始化失败→review 8s观察不到DV解码器→`HdrDegradedEvent(nativeDvUnavailable, HdrNativeDvReviewFailure(timeout))`→**ACTUAL=toneMapSdr**（两处一致+Applied事件）。播放恢复（Texture prepared/VIDEOPARAMS nv12 3840×1920 hlg sigPeak4.93），画面为tone-map SDR（沿用既有"颜色正常/卡顿严重"定性，非新直通画面结论）。**结论：P8.4走nativeDV的唯一阻塞=~/src/FFmpeg/libavcodec/mediacodecdec.c native_dv门仅放行P5单层；下一步=扩展该门接受profile 8（BL+RPU+无EL判据已在消息中解析）→增量重建libmpv JAR（native-dv-default-ps-build树）→R28装机重验；qcom DV解码器对P8.4输入的实际行为为扩展后开放问题**。归档p84-direct-run-r27b-20261007/（6文件，evidence-index 5181，experiments库d027aea已推送）。 adb shell logcat空=ROM已知特性，exec-out正常（再证）。
- **R26两条定性撤销+日志问题解决+r26b受控重验（2026-10-06深夜）**：网上检索（READ_LOGS限制/persist.logd.size/LG G4 logd替换均不适用）后受控冷启动实验一锤定音——**真因=R26构建脚本漏注入local JAR env**，APK缺产品libmpv，冷启动抛"Cannot find libmpv.so"（黑屏/超时/无日志全由此）；**exec-out日志通路完全正常**（新进程flutter行全可读），"LG关闭三方app日志"定性撤销、诊断落盘任务降级。r26b修正（env注入+lib hash校验）重验：初始化干净、**nativeDolbyVision路由链实锤**（hint sdrDirect→decoder→nativeDV选中→ACTUAL output dolbyVision/dynamic true）、画面推进零错误、Back严格退出全链、timeout恢复。**nativeDV画面人工验收待用户**（提问未答，可随时重播）。归档r26b（6文件，index 5175）。
- **LG logger专项轮完成（2026-10-06）**：按用户提供的LG G6/V20公开经验执行——persist.service.main/system/events.enable=1成功拉起三服务并激活/data/logger/文件旁路（main.log 5.9MB仅uid-1000系统行、events.log为events buffer旁路），但**三方app的main日志被独立关闭**（WWTEST写读不通、flutter 0行、logd buffer禁用不可经adb恢复）——R26黑屏根因的日志定性需app侧落盘机制，已登记新planned任务"HDR诊断日志落盘机制"。开关已恢复0。归档logger-round-20261006/（index 5169）。
- **R26 nativeDV直通实机验证（2026-10-06）**：成熟度解锁（dvP5×nativeDV→experimental；需求表"任意DV"行拆分同步+锁定测试32格+planner/policy/diagnostic测试反转或条件化；V2独立审核PASS+两LOW采纳）后实机。**结果：路由可达但呈现不可靠**——首轮播放推进过+hal_hdr激活，用户观察"锁屏前白屏、解锁后黑屏"；am start -W两次挂起；LG logger开关对R26新进程关闭（flutter日志0行阻断定性）；crash buffer空。处置：maturity保持experimental默认关（experimental门价值实证）、toneMapSdr兜底不变、根因需开logger专项轮。归档nativedv-direct-r26-20261006/（新库，index 5168）。**用户"A完成即收口"语境下A未顺利通过——LG上其余验证按原计划继续待排期（不因A触发收口）**。
- **R25直通方案实机验证完成（2026-10-06，用户导演）**：整理后HEAD构建HDR10直通包bd72c380（R19同款defines+当前产品lib7cc6f4ac；首建误用R19旧lib期望值6c8ec17e已修正），安装全字节核验+PQ素材fresh（76438009B/3068be37），实机路由baseLayerDirect/nativeHdr/PQ直出+hal_hdr激活+0 Stop失败，**用户结论"流畅，显示正常"**——直通（baseLayerDirect）vs tone-map（toneMapSdr 11.6fps卡顿）对比定性完成，直通流畅性通过。R17修复直通路径冒烟无回归。退出hal_native恢复+timeout30000/sleep。归档新库hdr10-direct-r25-20261006/（evidence-index 5164——注意evidence-index自身已随experiments迁至新库，后续归档路径用~/src/media-kit-experiments/）。
- **归档迁移（2026-10-05，用户指令）**：`archives/experiments/` 全量迁至独立仓库 `~/src/media-kit-experiments`（807MB/6308文件，构建缓存已清理见其CLEANING-MANIFEST.json）；本文及 TASKS 中所有 `archives/experiments/` 前缀路径均映射该库根。conversations 留主仓库。
- **全屏维度R24人工观察完成（2026-10-05，队列第3项，LG任务无阻塞项全部收口）**：P5_SCOPE_FULLSCREEN define专用包（APK ab21e434，R23同源树仅加define）安装核验+素材fresh+起播，AppBar全屏按钮UI dump确认（bounds [1248,112][1440,304] clickable）。**用户观察结论**：旧叠层消失✓画面全屏无遮挡、画面完整✓未见缺失、比例✓正常、退出全屏往返✓无异常；亮度不确定是否HDR（SDR tone-map路由预期，非缺陷）；帧率低卡顿严重（已知tone-map性能项low/deferred，非全屏回归）。Back语义观察：首次Back被fullscreen scope消费（先退全屏）、二次Back严格页面退出（onSurfaceCleanup wid2218 3840×2160→AUTO_PLAYER_DISPOSE completed→Launcher）、timeout30000/sleep恢复。归档5文件（evidence-index 5159）。**LG任务剩余仅Vulkan回归（无设备blocked）——全部无阻塞工作完成**。
- **N4观测轮R23完成（2026-10-05，用户批准队列第2项）**：观测增强实施（helper绑定撤销采样+backendStopIssued三态推导+page透传，lab 268/268+analyze零issue+独立审核PASS+两条LOW修复：gap文案区分未采样、值名inferred化）→R23构建（R22已审树+R17修复+N4增强两审核引用+fresh manifest，APK f717e718）→实机全链（R22 predecessor fresh→安装全字节→P5素材fresh→Run tap→settled→真实Close→final读回→Player终止→Launcher→sleep，run 1791188072374046-n4）。**新观测字段实机值**：backendStopIssued='issued-verify-failed-coordinator-error'（原unknown落定，stop已发出、验证失败于原债务StateError——负向语义保留）；boundOutputWithdrawnObserved=**true**（dispose前handle545803059792/gen1/viewId0/wid2099346→后全null，R21"未采不能追认"的tuple撤销观测实机首证）；controllerRetired=false维持Android平台定性（撤销观测补足retirement侧事实）；原债务/严格退出/Close按钮全保持。R17修复随轮冒烟：stop边界无错误、无回归。归档7文件（evidence-index 5154）+strict-predecessor-r23-v1。**仅剩：全屏维度（需专用包）、Vulkan回归（待设备）**。
- **R17 Stop失败根因修复完成（2026-10-05，独立审核PASS）**：根因=mpv stop返回时playlist同步清空但path属性待文件teardown才清空（实机谓词pathEmpty=false/entryEmpty=true+P5 r1日志codec拆链窗口佐证；审核确认外部并发加载假设不成立——锁内不可交错、绕锁加载会写entry被identity-changed拒绝）。修复=captureStoppedBoundaryUnderLock对"entry空+path非空"进入有界重读（100ms×5，锁内无副作用，player/entry/epoch任一变化仍抛identity-changed含完整诊断字段+rereads，超时保留原path-not-empty失败+计数）；entryEmpty=false组合原语义不变，尾部second检查保留。测试+4（滞后清空成功/永不清空失败rereads=5/entry重填/epoch变化），套件39/39，analyze无新issue，现有测试零影响（失败组合均entryEmpty=false）。独立Reviewer PASS（复跑验证；遗留：实机复验合并下轮构建轮、500ms上界待实机数据、identity-changed多轮重读消息字段代际cosmetic）。全量2失败已定性为工作区其它任务dirty（classifier源码+其测试、platform_view契约被检源码均在本修复未触碰的dirty列表）。
- **HDR10人工观察轮完成（2026-10-05，用户批准"先做需要观察的项目"）**：R19包f24b137f装回（全字节回读一致+lib按权威记录核验）、素材lg-pq-4k30 fresh流式校验（76438009B/3068be37）、两次进出路由稳定（baseLayerDirect/nativeHdr/PQ/platformView）、0次Stop失败、系统hal_hdr↔hal_native完整时序捕获。**三维度人工结论**：①时序亮度=无感知跳变（用户先最大亮度无变化、改自动亮度后盯进入瞬间仍无跳变——系统HDR激活但面板光学提升不可辨，正式关闭R18/R19"HDR状态未知"遗留）②Recents=卡片变黑（SurfaceView不参与卡片缩放，与历史texture路径通过形成拓扑对比，非回归）③全屏=该版包controls:null且全屏defines未启用，无入口可观察（配置事实）。Back严格退出+timeout30000/sleep。归档hdr10-observe-r1-20261005/（4文件含logcat HDR提取），evidence-index 5147。
- **P5 ACK采集轮完成+Surface ACK四分支全闭环（2026-10-05）**：按用户批准队列执行p5-ack-capture-plan-r1.md——构建门（源码fresh=R22审批manifest逐字节一致+R9 native）→P5 defines三件构建（APK 663126db…）→安装（p84退出状态前置核验+全字节回读）→素材fresh流式校验（289758635B/dacfd045）。r1播放启动失败：**Stop did not establish a stable empty source; reason=path-not-empty; pathEmpty=false; entryEmpty=true; firstEpoch=1**——R17间歇Stop失败P5素材首证+诊断谓词实机首证（R17时代三次失败无谓词记录的未解项直接回应）；错误态页面Back退出保留原错误（R7语义）。r2重试全链成功：预测sdrDirect→**实际toneMapSdr**（dynamic:true，P5 RPU语义，漂移待分析非阻塞）、Back严格退出（dispose handle545902434384→onSurfaceCleanup wid1986 3840×2160→AUTO_PLAYER_DISPOSE completed→WindowManager双destroy→Launcher）、timeout30000/sleep。**ACK四分支全闭环**：HDR10 R14/P8.4(PID17107)/N4失败R21/P5(PID3462)。归档p5-ack-r1-20261005/（5文件+ack-evidence.json）+P8.4人工验收manual-acceptance.json，evidence-index 5142。
- **P8.4人工画面验收完成（2026-10-05，用户实机重播后反馈）**：颜色正常✓、流畅性不通过（帧率低、卡顿严重——与量化实测11.6fps/61%掉帧/4824次underrun完全吻合）。重播后Back严格退出通过（onSurfaceCleanup→dispose完成→Launcher前台确认）、timeout30000/sleep恢复。P8.4最终定性：路由toneMapSdr正确、颜色正确、性能失败（tone-map系统性问题=用户已定low/deferred项的最终人工证据，量化基线音频underrun约4次/秒）。**Surface ACK四分支至此仅剩P5 texture分支**（用户批准队列第一项执行中，方案p5-ack-capture-plan-r1.md）。

- **最新P8.4普通Session实播轮完成（2026-10-05）**：用户授权defines（AUTO_SINGLE_PLAYER=true、HDR_TRANSACTION=true、LOCAL_SOURCE=/data/local/tmp/media-kit-p84-7626cac2.mp4三件，不设诊断/实验flags）构建 lg-p84-ordinary-session-r1-20261005（APK `c252ded1…`/lib7cc6f4ac/JAR23036e0b）。构建门=R22已审源码fresh一致（当前树与R22审批sources manifest逐字节相同，digest 11a22f66）+R9 native selection+intake b12db075普通入口只读核对+用户指定defines；R22 build approval（N4 defineContract）未继承。install predecessor=R22 strict fresh核验（设备N4 final 1bf3b9e1字节+Launcher）→安装后整APK/lib全字节回读一致。实播：P8.4素材fresh全流式读回（1232790317B/`7626cac2…`，600s有界）、stable-wake、am start、**hint→decoder verified升级**（hevc/hlg/bt.2020/dvProfile8/compat4/无EL）、**HDR_SESSION_ACTUAL=toneMapSdr与intake预测100%命中**：toneMappedSdr/output sdr/texture/gpu-next/mediacodec-copy/bt.709/bt.1886/stripRpu=true；四跳过原因逐项一致（unsupportedStrategy、displayLacksTransfer、gpuHdrDataSpaceUnavailable、experimentalStrategySkipped）。VIDEOPARAMS nv12 3840×1920 bt.2020-ncl gamma hlg sigPeak4.93（真实4K HLG基层解码）；MPVPROP tone-mapping=bt.2390、android-surface-size=3840×1920。120s观察窗7截图（1.4-2.9MB大小变化=画面在播非黑屏）+全程logcat（仅1条探测期mpv错误hevc_mediacodec surface/native_window NULL，随后解码器正常建立）。**Back严格退出通过**：app前台确认→Back→VideoOutputManager.dispose(17107/545800797264)→VideoOutput onSurfaceCleanup(id=0,wid=2218,3840×1920)→AUTO_PLAYER_DISPOSE completed→Player disposed→插件detached→WindowManager双surface销毁→Window went away→Launcher前台（PopScope strict disposal语义clean才pop）、零flutter错误、timeout30000核验/sleep。Surface清理链可按PID/handle/wid关联（app侧onSurfaceCleanup+系统侧destroy），但无显式release ACK行，仍不等于R14模式的ACK独立关联。精选9文件归档 `archives/experiments/artifacts/lg-hdr-20261004/p84-ordinary-session-r1-20261005/`（route-evidence.json含全部结构化事实），evidence-index 5134；截图/完整logcat留本机（含屏幕内容不推送）。**缺口如实保留**：人工画面/颜色/流畅验收pending（需用户）；Surface ACK未按R14 PID/handle/wid模式独立关联（仅WindowManager destroy surface）；全片EOS未观察（120s窗后Back）；drop计数未采（无性能诊断defines，tone-map性能用户已定deferred）。**截图Vision辅助判读（2026-10-05 team-vision，辅助参考非人工验收替代）**：7张三维度结论——完整性正常（无花屏/撕裂/马赛克/缺失）、颜色正常（各场景SDR观感合理无整体偏色、screen-5天空渐变无明显色带）、比例正常（2:1 letterbox一致无裁切拉伸）、画面持续推进（6镜头+字幕变化）；不可判断项如实保留：光学亮度、HDR显示状态、流畅性（静态截图不承载）；观察项：截图实测1440×2880与dumpsys窗口2672不符（采集配置差异不影响判读，留核对）。
- **交接入口**：用户要求切换agent，完整交接见 archives/experiments/lg-hdr-agent-handoff-20261005.md；本次提交推送LG记录与精选审核索引，未提交源码保留当前工作区及 /Users/wuweiwei1/src/media-kit-build/lg-api24/handoff-local-snapshot-20261005/。不得覆盖其它dirty。布局独审24PASS已实际终态、无独立analyze（作者Noissues），正式freeze PASS REVIEW12ade35b/export162ac461，Root全manifest核验归档，全部agent终态；设备无新播放。
- **最新R22实机轮完成（2026-10-05）**：按冻结approval7ade7443串行执行全链——fresh容量2.7GiB核验后实际构建（Gradle assembleRelease 56.6s exit0，APK `7a0164f0fbb79d0188f0ded840fa5349da907ee675fa323e1008c54491de9890`/lib7cc6f4ac/JAR23036e0b，嵌入lib逐hash与审批一致）、install-verified（R21 predecessor fresh设备final字节9f2c833f…核对+Launcher前台前置、安装后整APK/lib全字节回读一致）、launch-verified（P5素材全流式读回289758635B/dacfd045通过、stable-wake、唯一Run按钮真实tap，新run `1791143551454881-n4`≠旧run防stale）、N4实验settled（route nativeDolbyVision）、**真实Close按钮一次tap成功**（R21 P2裁剪不可达由R22布局修复实机闭环）：final读回SHA `1bf3b9e1…`、44条journal零截断、外来FILE_LOADED(entryChanged/epochAdvanced/pathMatchesSameP5Uri、同Session代次)与owner-stop refusal(原StateError债务保持)完整、player-termination completed、Launcher前台、Close序列finalCloseErrors=0、timeout30000恢复/sleep。strict-predecessor-r22-v1凭据已生成供未来轮次。n4DeviceAcceptance仍not evaluated/surfaceAck unverified（工具边界非缺陷）。时序教训：N4 settled后无播放保持唤醒，30s熄屏使uiautomator dump拿SystemUI——capture第3采样与首次verify-closed因此失败留证（n4-session-capture-r22/n4-session-close-r22保留），唤醒后30s内重跑全过；Close后launcher检查一次竞态1s重试成功（lastObservationError留证）。R22精选11文件已归档 `archives/experiments/artifacts/lg-hdr-20261004/n4-session-release-r22-20261005/`，evidence-index增至5125。
- **设备/最新实机**：LG当前安装R22（label lg-p5-n4-layout-r22-20261005），已sleep/timeout30000。R21历史负向与Back退出凭据保留于n4-current-predecessor-r21-v1；当前设备核验以strict-predecessor-r22-v1为准（fresh读回仍必须）。
- **当前源码/工具**：page6ccc5327（N4 Run/Close移出滚动诊断区），helper e37b3333/test02b2c02f保留身份与最后await后同步复核；当前布局独审12ade35b/export162ac461限定PASS。作者73952 16PASS/77515Noissues、独立52491 24PASS实际终态。R22-bound八生产scripts同v2字节，仅导出table换当前源码review；旧R21工具/审批与所有失败证据保留，不继承其新包验收。
- **HDR10现有验收**：R19 run1791133724150506原生输出PQ6/HDRflag0；用户完整画面、2:1比例、颜色、流畅性正常，亮度看起来不错、HDR状态未知。R18 profile原生transfer3/HDRflag1，用户除HDR状态外其它正常。R17两次Stop边界失败→SDR/卡顿保留；R18/R19成功不能证明诊断修复了间歇问题。
- **显示独立证据**：REVIEWfa720ee6/manifest61161106完整核验归档。R18/R19当次系统hal_hdr/LUT/HWC tone-map正证据位于切换交叠期；稳定R19同APK采证原生binding前后相同、HWC3840×1920→1440×720，Close后video layer移除。stock SF/display未暴露owner-bound持续HDR/dataspace；lgdisplay/display.qservice存在但默认dump空。面板持续HDR/光学亮度未证，不合color/profile或改默认。R18/R19 Java releaseACK已按PID/handle/generation/wid独立关联，但journal仍unverified，非SF内存回收证明。
- **素材核验**：固定P5设备289758635B/SHA256dacfd045已在74579及45750两次prelaunch流式完整读回通过，首轮约61.45s；较早Root63631内存式全读90s超时保留，sha256sum/toybox applet不存在。后续操作仍fresh校验，不以size或历史hash替代。P8.4已完整stage1232790317B/SHA7626cac2，普通Session实播未做；API24无HLG声明、SDR fallback仅预测。
- **此前已通过**：P5普通原生播放、Home回同Session单ManualResume后连续播放人工确认；N1真实约10s超时→SDR回退、配置恢复及严格退出通过，画面/颜色正常但tone-map卡顿。R7失败启动Close/Back保留原error/debt并终止/返回桌面通过。更细版本与证据见ledger/history，不向其它分支扩大。
- **P8.4准备完成**：REPORTb12db075冻结归档，实际Dart命名fixture命中p84/exit0；普通Session最小defines已在交接中，无需新增专用JSON。默认API24预期SDR仅预测，实际路由与人验仍缺。唯一连接设备LG，现代Vulkan输入仍缺。
- **N4 retirement观测定性**：只读REPORT34ea17cf已核验归档。Android未更新nativeSurfaceActive，wrapper透传false，R21 false→false不作退役失败；不是身份混层问题。公开currentBoundOutputIdentity可观测Session.dispose前后绑定撤销，但R21未采不能追认，且撤销不等于ACK/资源全释放。保留旧false/未知，不改共享底层API；当前先完成按钮实机与普通Session验收，新增tuple诊断非功能阻断。
- **仍需完成**：P8.4与R22人工画面验收（需用户）；HDR10剩余时序及显示状态；Recents完整frame/亮度、全屏完整/旧叠层消失/亮度；**Surface ACK分支定性（2026-10-05深挖）**：R14两阶段acknowledgeSurfaceRelease属HDR10 PlatformVideoView(SurfaceView)路径；P8.4 toneMapSdr=texture拓扑无PlatformVideoView，其对应清理证据=onSurfaceCleanup(id=0,wid=2218)+VideoOutputManager.dispose(handle 545800797264)+WindowManager destroy链（已按PID 17107关联在案，P8.4分支视为已闭环，形态差异源于拓扑非缺失）；N4失败分支R21 tuple确认在案（R22同模式未单独采logcat，与R21语义同源）；**仅P5 texture分支的ACK未单独取证**（需一轮P5播放+退出logcat采集，排人工验收后）；N4整体设备验收观测（nativeStopIssued/controllerRetired维度）；现代Vulkan设备回归。tone-map性能按用户要求low/deferred后移。交接记录3e6be578已推送，R22/P8.4轮记录更新未提交（无本轮提交授权）。

## Evidence

- 原始证据：archives/experiments/artifacts/lg-hdr-20261004/。
- 官方DV素材：~/src/media-kit-build/sources/media-kit-dolby-official-p5-2160p.mp4，ffprobe确认DV5/RPU/BL/compat0。
- PQ素材：Downloads/test-clips/【4K HDR】哔哩哔哩 真·HDR ON！！这才是看世界的正确方式｜地球Online 光线追踪极限画质｜4K HDR演示片｜屏幕画质测试｜Links.mp4，前30s stream copy到~/src/media-kit-build/sources/lg-pq-4k30-30s.mp4，不重编码。


## Next

**当前等待用户人工画面验收（2026-10-05 登记；设备与材料已备齐）**。操作指引：

1. **P8.4 画面验收（现装包，零准备）**：唤醒手机（无密码锁屏）→ 打开 media_kit_hdr_lab → 自动开播 P8.4 素材 → 观察至少1-2分钟，判断三点：①颜色是否正常（预期 SDR 观感，tone-map 后 BT.709，不应偏色）②画面完整性（无花屏/缺失/比例异常；素材为 3840×1920 即 2:1）③流畅性（tone-map 卡顿为已知可能项，如实反馈即可）。验收完按系统 Back 退出（严格清理已技术验证）。不便操作时可直接看留档截图 `~/src/media-kit-build/lg-api24/p84-session-run-r1/screen-0..6.png`（120s观察窗7张，1.4-2.9MB画面变化）。同轮可顺带：播放中按 **Recents** 键看卡片画面完整性/亮度，全屏切换看**旧叠层是否消失**与亮度。
2. **HDR10 时序亮度**：需 HDR10 世代包（现装为 P8.4 包；R19 color APK f24b137f 本机留档可装回或按需新构建）——待 P8.4 验收结论后排期换包执行。
3. 人工验收通过后依次排：**P5 texture 分支 Surface ACK 采集轮**（唯一剩余分支；HDR10 R14/P8.4 texture链/N4失败分支R21 tuple均已闭环，见"仍需完成"定性）、**N4 整体设备验收观测**（nativeStopIssued/controllerRetired）、**现代 Vulkan 回归**（无设备，待到位）。tone-map 性能维持用户既定 low/deferred。

## History

### 2026-10-06 R26撤销与r26b受控重验：真因=构建缺陷，nativeDV路由实锤

用户目标"网上搜寻LG日志解决方案并解决"。检索三条候选（READ_LOGS/persist.logd.size/LG G4 logd替换）均不适用后，重审证据：R25（同方式）可读flutter而R26不可——受控冷启动实验：force-stop+重启后flutter 33行可读→再冷启动抓到"Unhandled Exception: Cannot find libmpv.so"（native_library.dart:83）→**R26坏包实锤**（脚本漏ORG_GRADLE_PROJECT_mediaKitLocalArm64Jar，Gradle回退上游Maven）。修复（env+embedded lib hash校验）重建r26b：lib 7cc6f4ac核验、安装全字节、受控冷启动——初始化干净、路由链nativeDolbyVision选中、ACTUAL=output dolbyVision、画面推进零错误；Back#1被fullscreen scope消费+Back#2严格退出（dispose completed/双surface销毁/Launcher）、timeout30000恢复/sleep。两条R26定性撤销（呈现不可靠+LG关app日志）；诊断落盘任务降级。nativeDV画面人工验收遗留待用户（AskUserQuestion未答）。

### 2026-10-06 R26 nativeDV直通实机验证：路由可达但呈现不可靠

V2审核PASS后实机（R26包b0dae803：P5三件+GATE_OPEN，默认偏好序dvP5首位nativeDV）。首轮播放推进+hal_hdr激活（路由可达性再证），但用户观察锁屏前白屏/解锁后黑屏——DV呈现跨息屏循环不可恢复；am start -W两次挂起（冷启动异常）；LG logger开关对新进程关闭（flutter日志0行）阻断日志定性；crash buffer空。处置：maturity保持experimental（默认关），toneMapSdr兜底不变；根因定性需开LG logger的专项轮。归档nativedv-direct-r26-20261006/（index 5168）。

### 2026-10-06 R25直通方案实机验证：整理后代码直通流畅

用户导演流程（纠正：不重复验证旧包，验证整理后代码+说明直通状态盘点）。直通状态盘点（LG API24）：HDR10 PQ已验证直通/SDR基线；HLG基层直出被displayLacksTransfer+gpuHdrDataSpaceUnavailable设备门禁拒绝；P5→PQ reshape被experimental门禁跳过（LYA已验证同路径）；nativeDV仅N4诊断模式路由已达画面未验证。构建整理后HEAD直通包（R19 defines+当前产品lib），实机：路由baseLayerDirect直出PQ+hal_hdr激活+0 Stop失败（R17修复直通路径冒烟无回归）+hal_native退出恢复。**用户结论：流畅，显示正常**——直通vs tone-map对比定性与量化证据（11.6fps）互相印证。归档新库（5文件，index 5164）。

### 2026-10-05 全屏维度R24：人工观察四项全过，LG无阻塞队列收口

用户批准队列第3项。源码树=R23同源（R22已审+R17修复+N4增强两审核引用），仅加MEDIA_KIT_ANDROID_P5_SCOPE_FULLSCREEN define（AppBar全屏按钮+标准toggleFullscreen）。全链：R23 predecessor fresh→安装全字节→P5素材fresh→起播→UI dump确认按钮→用户观察→双Back语义（fullscreen scope消费首Back+二次严格退出）→Launcher→timeout/sleep。用户结论：旧叠层/完整/比例/往返全过，亮度不确定=SDR预期，卡顿=已知deferred项。LG任务全部无阻塞工作完成；仅剩Vulkan回归（无设备）。

### 2026-10-05 N4观测轮R23：两个未知维度实机落定

设计（按此前定调的最小路径）：public currentBoundOutputIdentity在Session.dispose前后采样（platform.future→AndroidVideoController→同步快照，异常安全null），撤销三值语义+gap规则；backendStopIssued从dispose report推导三态+basis明示非核心遥测。测试：fake onDispose注入撤销（_FakePlatformOutput已有可写identity），+2测试+2构造修补，lab全量268/268、analyze零issue；独立审核PASS（复跑验证、fake真实性评估、NOTE-3设备轮异步沉淀窗口属验证范围）+两LOW采纳。实机R23（R22树+两delta、R22 approval不继承）：全链过，run 1791188072374046-n4。实机新值：withdrawn=true（tuple撤销首证）、backendStopIssued=issued-verify-failed（原债务StateError保留）、controllerRetired=false平台定性不变。R17冒烟无回归。两次脚本失误留证（r23先等settled后Run顺序错、r23b未退app致predecessor Launcher拒绝——防护正确工作）。strict-predecessor-r23-v1生成。N4观测缺口关闭。

### 2026-10-05 R17 Stop失败根因修复：定位→修复→测试→独立审核PASS

用户批准队列（R17根因→N4观测→全屏包）。根因分析：读captureStoppedBoundaryUnderLock/_readOptionIdentity源码+P5 r1谓词——mpv stop命令playlist清空同步、path属性清空滞后于teardown，谓词组合精确吻合；现有二次读一致性检查无法区分"稳定的空"与"稳定的旧值"。修复（最小保守）：entry空+path非空时有界重读100ms×5（锁内、无option写、全identity维度变化仍失败、超时保留原失败+rereads计数）。4个新测试+39/39+analyze干净+现有测试零影响（其失败组合entryEmpty=false不进重读）。独立审核PASS（含复跑；根因替代解释排除；风险：最坏600ms锁持有vs现状硬失败，锁内await有先例无死锁面）。全量测试2失败定性为其它任务工作区dirty（classifier/契约源码）。实机复验合并下轮构建。

### 2026-10-05 HDR10人工观察轮：时序亮度/Recents/全屏三维度落定

用户排期"先做需要观察的项目"。装回R19原包（身份三重核验），两轮播放观察：亮度维度用户两次反馈（最大亮度基线无变化→改自动亮度→进入瞬间无跳变），结论=系统hal_hdr激活但面板光学无可感知提升，关闭R18/R19遗留问题；Recents卡片变黑（用户观察）定性为SurfaceView拓扑行为（历史Recents通过均为texture路径）；全屏无入口=controls:null配置事实。附带系统侧完整HDR时序（进入hal_hdr/退出hal_native两次循环）与路由稳定性证据（两次进出baseLayerDirect一致、0 Stop失败——本轮未复现R17间歇问题）。严格退出+恢复。归档+记录同步。

### 2026-10-05 P5 ACK采集轮：四分支全闭环+R17谓词实机首证

用户验收结论（颜色正常/卡顿严重）后按批准队列执行。构建门=源码fresh一致+R9 native+用户批准方案；P5 defines三件（无诊断flags）。r1：播放启动即遇Stop边界失败，诊断谓词首次实机落盘（reason=path-not-empty; pathEmpty=false; entryEmpty=true; firstEpoch=1）——R17 HDR10间歇失败同款签名在P5素材复现，且R17时代"三次失败谓词未记录"的定点诊断诉求获得直接答案；错误态Back退出保留原错误。r2：全链成功，路由预测sdrDirect实际toneMapSdr（dynamic:true，P5 RPU语义），ACK清理链完整（PID3462/handle545902434384/wid1986，surface 3840×2160与P5素材匹配、与P8.4的1920可区分）。Surface ACK四分支全闭环。剩余：N4设备验收观测（需改码）、HDR10时序轮（需换包）、Recents/全屏人验、Vulkan回归；R17 Stop失败根因为独立后续项（现有谓词证据支持定点分析）。

### 2026-10-05 P8.4人工画面验收完成（用户实机重播）

用户要求重播验收：唤醒→am start→自动开播（画面推进+解码活跃确认）→用户观看后反馈"帧率低，卡顿严重，颜色看起来正常"→Back严格退出（dispose完成回Launcher）→sleep恢复。颜色=人工通过；流畅性=人工失败（与EOS轮量化三互证完全吻合，构成tone-map性能项最终人工证据）；完整性未单独提及（Vision判读正常在案）。TASKS/handoff同步。

### 2026-10-05 P8.4 EOS观察轮：未达EOS+极端tone-map性能劣化量化实证

R1轮后为补"全片EOS未观察"缺口执行EOS观察（现装包零阻塞）：attempt1（eos-verified.py，04:29:54开播、1320s窗）AUTO_COMPLETED标记未出现且窗口尾解码活动仍在；诊断确认画面推进中（双截图不同）后attempt2（eos-wait2.py被动等待+解码idle备份判据，1200s窗）仍未EOS，按超时路径Back严格退出成功（dispose链handle 545917655120/wid2242、AUTO_PLAYER_DISPOSE completed、WindowManager双surface销毁、Launcher、timeout30000/sleep、零flutter错误）。**定性（非循环非停帧——VIDEOPARAMS无新开播）**：04:29:54→05:13:57共44分钟wall-time未完成19.5分钟素材（推进<0.44x），AudioTrack同句柄0x7f13852480 start()重启**4824次**（约250ms间隔持续underrun），C2DColorConvert错误04:53:51→05:13:57连续——**帧率量化（补）**：C2DColorConvert错误13955条/1205.6s=11.58次/秒（每帧色转一错），实际渲染约11.6fps vs 源29.97fps（掉帧约61%），与wall-time 0.39x推进及250ms underrun三者互证；**LG API24 toneMapSdr路径软色转瓶颈完整画像：~11.6fps渲染/61%掉帧/音频4次每秒underrun/0.39x推进**，为tone-map卡顿已知项（用户R8/R10报告、已定low/deferred）提供系统性证据。EOS缺口以"性能受限未达"关闭（两轮脚本结果+量化证据eos-round-evidence.json归档eos-round/，evidence-index 5137；完整logcat 7.6MB留本机）。对人工验收的预期管理：流畅性维度大概率不通过（有量化依据），颜色/完整性Vision判读正常，光学亮度/HDR状态仅用户可判。工具脚本eos-verified.py/eos-wait2.py入p84-session-build-r1/。

### 2026-10-05 P8.4普通Session实播轮：toneMapSdr路由实机确认与Back严格退出

用户授权defines三件（不设诊断/实验flags）构建安装实播。构建门：当前源码树与R22审批sources manifest逐字节一致（fresh drift-check通过，digest 11a22f66）+R9 native（JAR23036e0b）+intake b12db075+用户指定defines；R22 N4 approval未继承（defineContract不同）。构建exit0（APK c252ded1）、安装（R22 predecessor fresh前置+全字节回读）、素材fresh全流式校验（1232790317B/7626cac2，600s有界）、am start（ThisTime 976ms）。路由实机确认=预测100%命中（toneMapSdr选中，四跳过原因逐项一致）；decoder verified升级（hevc/hlg/bt.2020/p8/c4/无EL）；VIDEOPARAMS nv12 3840×1920 bt.2020-ncl hlg sigPeak4.93；tone-mapping bt.2390生效。120s观察7截图+logcat全程（仅1条探测期mpv错误）。Back严格退出：VideoOutputManager.dispose→AUTO_PLAYER_DISPOSE completed→Player disposed→WindowManager双surface销毁→Launcher、零flutter错误、timeout30000/sleep。9精选文件归档项目（route-evidence.json），evidence-index 5134；截图/完整logcat留本机。缺口：人工画面验收pending、ACK未按R14模式关联、EOS未观察、drop未采。工具脚本 p84-session-build-r1/（build-release/install-verified/run-observed/close-verified，复用r22-bound冻结契约模块做源码/native核验）。

### 2026-10-05 R22实机轮：构建/安装/真实Close按钮验收全链通过

Lead按冻结approval（SHA7ade7443核对一致）串行执行：①fresh容量2.7GiB（R21构建后2.83GiB同量级，增量构建热缓存）；②check-only exit0后实际构建56.6s exit0，APK7a0164f0/JAR23036e0b/lib7cc6f4ac嵌入hash与审批一致；③install-verified exit0（R21 predecessor fresh设备final字节+Launcher前置、安装后整APK/lib全字节回读一致）；④launch-verified首跑因install确认间隙熄屏Launcher检查拒绝（n4-session-launch-r22留证），唤醒后r22b目录重跑exit0：P5全流式读回61s通过、stable-wake、唯一Run tap，run1791143551454881-n4；⑤N4 settled（route nativeDolbyVision）；⑥capture-journal 2/3采样成功（native-session-0/1+ui-0/1），第3次因settled后30s熄屏dump失效失败留证；⑦verify-closed首次同样熄屏失败（n4-session-close-r22留证），唤醒确认app前台/唯一run token/Close按钮存在后r22b重跑exit0：真实Close&exit一次tap、final 1bf3b9e1读回、44条journal零截断（外来FILE_LOADED三事件链+owner-stop refusal原StateError保持+player-termination completed+closed）、Launcher前台、timeout30000/sleep恢复。strict-predecessor-r22-v1生成；11精选文件归档项目archives，evidence-index 5125。n4DeviceAcceptance not evaluated/surfaceAck unverified为工具边界如实保留。源码及其它dirty未动，无新提交。

### 2026-10-05 R22构建门收尾

REVIEW80c229af/approval7ade7443正式限定PASS，28092实际exit0。Root核验全部manifest引用并归档，未执行构建/安装/播放。两审核fixture错误完整留证，所有agent终态。

### 2026-10-05 R21负向与外部Surface ACK独审完成

R21独立runtime审核718e5aa1/manifest401c7f3f已逐hash核验归档：N4外来FILE_LOADED、同Session代次、native_dv/timed保持、owner-stop拒绝、原StateError债务与严格Back退出通过限定审核。vo/null和hwdec空不称全部属性保持。当前PID13871/handle545802965584/gen1/wid2099318在03:00:27明确released/acknowledged，属于自动dispose阶段，不是03:05 Back新ACK。原final不改，n4DeviceAcceptance=false、controllerRetired=false/nativeStopIssued未知保留。Close按钮不可达P2待布局修复及真实按钮验收。 原page作者已接收最小布局工作包，未构建/设备。

### 2026-10-05 R21构建前上下文整合（旧快照，仅历史）

- **设备/安装及最新N4**：LGH870DS42e27764/API24，R20 APK10eb8772/lib7cc6f4ac已安装；R20 stable-wake实机：51890 exit1但wake成功、完整APK/P5 SHA通过，run1791137828694256-n4 Run按钮disabled/45s未admit且未执行N4；用户本轮颜色正常、流畅。63063 fullrun唯一Close/final JSON读回/Player终止/Launcher通过，status closed-without-explicit-test/result null/session clean true，仅未执行退出验收，不算N4通过。24138首次Close只fullrun断言拒绝无tap（v1 ui_run数字regex截掉-n4）；原证据保留。80262日志deadline父exit0/child-15；timeout30000恢复/readback/sleep；Root全部handle终态。N4准入与host完整run解析只读根因工作包已交原author，旧审批/源码不改。
- **N4准入根因/修复中**：真实R20 journal index22 consumer-validated accepted=false、index23 route-applied verified=true但accepted=false；源码比较VideoController wrapper与evidence中的AndroidVideoController，层级不同必拒绝，原fixture混层掩盖。诊断REPORT3d0b33c9已全文核对并归档；保留wrapper身份与platform对象及五元组分别校验，原page作者唯一修helper/page/相关双层测试，保留Session/gen/source/binding门；普通Session/backend/API/默认不改。另一writer只新host patch包修ui_run/anchor完整digits-n4，旧工具/审批不动。runId候选REPORT6dc86b76/8host tests+standard patch dryrun exit0/原始日志已核验归档，原工具reviewer独审中；源码修复已落，82825初始41PASS/1fixture late-final赋值失败保留；42026修fixture后三文件实际exit0/42PASS，56932 limited analyze实际exit0/Noissues，全部author handle终态，仅formatzero/diff/hash/REPORT冻结待完成；source REPORT506f9cf8/helper945c4c17/page1bfb55d7/testd599d40e正式freeze停写/Flutter释放，Root核验全部artifact并归档，原source reviewer正式独审已启动。3421新source intake仅3文件delta/0removed，digestdd85d03a，approvedForBuild=false，待review再绑定新工具。工具review同步actual exit0/标准isolated apply+20独立cases PASS，最终report待freeze。两包需源码/工具独审后新build，当前不再播放。
- **N4源码复审与第二轮修复**：首稿独审REQUEST_CHANGES（REVIEW680488dd），8029实际反例证明_captureBoundary最后time-pos await使currenttuple=null后仍rawopen1次；19914analyzeexit0/Flutter已释放。Root核验11项冻结引用并归档。原writer narrow47374旧基线exit1，tuple/native/wrapper/gen/Close五类漏检，epoch门已有拒绝；原log保留。helper已加最后await后同步再校验原Session/gen/sourceepoch/Close及wrapper/native/Player/currenttuple，不新增await；page不变，33921三文件实际复测exit0/48PASS，六类capture漂移均拒绝无open且原错误保留，3907limited analyze实际exit0/Noissues，REPORT-v2 013b7abd/helper e37b3333/test02b2c02f正式freeze/Flutter释放，Root14artifact核验归档，新3421sourceintake396df327 pendingfalse；原reviewer75655实际exit0/F1切口false/open0，74117实际exit0/48PASS，60204limited analyze运行。v2旧exporttable绑定旧13980及旧page/helper导致expectedfailclosed拒绝，source reviewer获授权若PASS补现有格式current4source导出契约证据，Root再绑定396df327新源；不改guard/继承旧审批，尚未新source批准/build/设备。
- **N4第二轮源码/导出契约正式PASS**：REVIEWa450abfb/manifest6eb85320，75655反例false/open0、74117 48PASS、60204Noissues均actualexit0/Flutter释放；exportreview6c9b268d/manifest4e6327ce绑定current4源，writer/CloseSequence/报告退出片段逐字节未变。Root全文读并逐hash核验两manifest/归档。新source396df327 pendingintake尚approvedfalse；v2 host python -Werror实际exit0/8PASS/0外部subprocess，首次fixture deadline范围错误保留；作者仅收尾diff/manifest/report freeze，待其停写后Root更新exporttable/source版本、再工具构建独审。不继承旧审批，不宣称deviceN4/ACK。
- **N4 R21构建前工具最终绑定**：作者v2 REPORT3ed4a24a/20artifact freeze/host8PASS/0外部subprocess，Root全hash核验归档；保留原作者冻结table，新v2-bound production同字节，只绑定新exporttable ACA0c2af/current4source reviews与whole396df327，工具canonical52f05bf4/bindingec741204。Root实际export_contract通过/whole3421源一致、Java17.0.20.1核验。原工具reviewer正式n4-session-build-review-v2审核label lg-p5-n4-controller-r21-20261005；尚无buildapproval/构建/设备。
- **N4当前工作**：helperddf66a96/page与external writer bfc7c8ef已独立限定源码PASS，20直接/页面测试与analyze通过。v1设备工具REPORTc15fdab3/manifestc04890d2及构建独审a43f6e5d/approval71f42749已冻结核验；R20实际APK10eb8772已安装。两次launch74579/45750均fullP5SHA通过，但首次window读keyguard=true即拒绝，无anchor/amstart/Run；后读keyguardfalse，支持异步唤醒采样race。作者仅独占新n4-stable-wake-launch-v1，添加独立15s实际状态等待，其它流程复用冻结v1/R20，待host/独审，无新build。永久rawopen pending仍非有界退出成功。

- **R20构建及前置失败证据保留**：APK实际72215buildexit0/9371安装exit0。两次prelaunch退出及源P5bytehash、初期安装Launcher拒绝、醒屏早读检查、恢复timeout已归档n4-session-release-r20-prelaunch；旧工具42/45host覆盖缺口、IO.final修正和最后13case记录在正式REPORT。旧Current State N4段（仅历史）：
- **N4当前工作**：helperddf66a96与旧page636f23fa独立源码/host限定PASS；最小external finalwriter已冻结pagebfc7c8ef/newtestbf9f40b9/REPORTd08e300b，仅两hunk，保留payload/Close顺序/失败不pop；作者8+12测试/analyze通过，独立审核已限定PASS（REVIEWc07c385a/manifestf6b8dae6，34646二十testsPASS/9689分析无问题，均exit0/Flutter释放）。工具作者独占n4-session-device-tools-v1，旧host45PASS/0外部subprocess已落，仅历史有限范围；Root发现长素材校验前唤醒可能在启动前重新锁屏，作者正调整顺序；Close anchor允许过期但必须绑定serial/label/120s结构门也待最终反例。已最终冻结REPORTc15fdab3/manifestc04890d2（旧7cda撤回），wake顺序/Close身份最终13反例PASS；独立tool/source/native构建Reviewer已正式单版本审核，Root发现IO.final机械替换调用错误，作者已修正并补真实I/O seam成功/拒绝fixture，首42反例覆盖不足记录保留；选择R9实证P5 JAR23036/lib7cc6；新构建门独立PASS（REVIEWa43f6e5d/approval71f42749/manifestb282c5f2）已全文读/核验/归档；Root正式R20build72215exit0/APK10eb8772已安装；label lg-p5-n4-external-r20-20261005；首次74579 launch在wake校验失败前停，无anchor/amstart/Run；全P5实读61.45s/289758635B/SHA dacfd045通过，后读实际Awake/ON/keyguardfalse。第二45750当前运行，未因观察到期重启实际播放。永久rawopen pending仍非有界退出成功。

### 2026-10-05 N4构建前 Current State 历史快照

旧 Current State（仅历史定位，非当前状态）

- **N4 external writer已冻结/交独审**：pagebfc7c8ef/newtestbf9f40b9/最终REPORTd08e300b；相对旧636f23fa仅两hunk，原payload/Close顺序不变，生产小writer外部目录/nullguard/mkdir/tmpflushrename，成功后公布path。作者24588八PASS/56846十二PASS/4040分析无问题，首76206失败fixture已修正留证；report补说明hash更新不偷用旧efb。独审正独占Flutter跑定向验收。N4工具选择实证R9 JAR23036/lib7cc6，不使用仅HDR10实测R15；新Dart兼容/实机未知。Root固定P5本轮63631完整读90s超时exit1，设备online/size289758635但freshSHA256未证；sha256sum缺失/toyboxexit127。工具改prelaunch流式host全hash有界300s并保存partial/failure，尚未新实读。

- **显示独审已冻结/归档，N4 writer进入实施**：REVIEWfa720ee6/manifest61161106逐项hash回读通过，R18/R19系统HDR处理正证据+稳定HWC原生图层/2:1+postClose图层移除，但无owner-bound持续HDR/dataspace/光学值；不合并参数/改默认。R18/R19外部Java releaseACK按当次PID/handle/gen/wid已关联通过，journal仍unverified且非SF回收证明。N4导出设计3323d996已全文读/归档，最小externalapp诊断目录/nullguard/mkdir/tmpflushrename方案；唯一page writer只改目的地及实际writer直接测试，Flutter定向独占，不build/ADB。新pagehash将使旧APK源审批失效。

- **厂商显示服务只读盘点**：lgdisplay/display.qservice服务存在，无参数dumpsys均exit0但无状态输出；仅默认dump信息缺口，未调用未知Binder事务/改设置，不据此否定HDR。R18/R19独审新增稳定display章已Root全文核对，待作者最终freeze；JavaSurface release/ACK可按PID/handle/gen/wid外部关联，不等于SF内存回收。N4工具及final外部读回设计继续。

- **N4进入设备工具准备**：重新核验page636f23fa/helperddf66a96/backend4d37df51冻结字节一致；工具作者独占新n4-session-device-tools-v1，仅host草案/反例，不构建/ADB/改源，默认审批拒绝。固定P5/真实Session+N4且排除其它实验，mode0原生依赖待精确核验。发现N4 final用私有ApplicationDocumentsDirectory，与normal诊断外部目录不同，Release shell读回存在缺口；已分派只读最小导出设计，尚未修改。永久rawopen pending仍不能假有界退出。

- **R19同包稳定显示采证已完成**：全APKhash重新核验f24b137f，新run1791134340140738；before8168ms/after28168ms同native绑定tuple，六display上下文dump均exit0，SF/HWC视频3840×1920→1440×720但不暴露dataspace/HDRmetadata。首次Close选择text失败无tap、71356观察超时保留；修正实际content-desc唯一tap1后closed-readback严格终态通过。postclose六dump通过（外层误touch路径exit1留证），日志62476explicitstop终态、timeout30000恢复sleep。无新人验；原R19人验仅属于前run。独立显示输出审核继续。

- **R19显示服务新证据待独审**：本次PID7068播放01:08:46.193，SDM PID559设置hal_hdr，随后LIBHDR_TM执行HDR策略/3D LUT及HWCToneMapper；支持系统HDR处理被启用，不证明面板光学亮度或metadata合规。550nits仅日志策略参数。R18/R19新证据独立审核正在进行，不盲目合并color/profile。

- **最新R19 color诊断已安装、实播并关闭**：APKf24b137f/lib6c8ec17e安装80696完整回读一致；run1791133724150506，Surface0+1输入/输出color6/6/2、输出PQ transfer6/HDRflag0/static25B，无Stop失败。用户亮度看起来不错、其它全部正常，HDR状态不确定；完整画面/2:1比例/颜色/流畅性通过，HDR显示状态未证。67039 strictClose exit0/cleanupVerified=true/error=null；2446日志deadline终态，timeout30000读回恢复并sleep。历史R18 profile输出transfer3/HDRflag1，人验其它正常、HDR未知。

- **历史R17 profile已安装/关闭**：APK4289a82c/libaa5da5bb/JAR12951151，install27809完整回读一致；run1791132475391629 actualmode2/gate1/applied2/status0/profile4096，copy decoder HDRflag1、无打印color字段。native切换在1.451s报Stop did not establish a stable empty source→同代SDR gpu-next/mediacodec-copy，无Surface1configure，不能原生HDR通过。用户颜色正常、不流畅/HDR无法确认；性能low保留。76960 strictClose真实恢复/终止/Launcher通过、log74839终态、timeout30000恢复并sleep，无Rootlive。此前R16为历史成功颜色映射对照。

- **历史R16 color实测**：install34164 exit0，pm base.apk-1、完整APK791c3160/lib6c8ec17e/JAR0a7d8c99读回一致，label lg-hdr10-input-color-r16-20261005；run1791132278693947实际参数gate1/applied1、outputPQ6，人工其它正常/HDR状态不确定；strictClose14142通过，timeout30000恢复并sleep。R17 profile build9390 exit0，不改变手机当前安装。R15以下为历史已验收基线。

- **最新优先级**：用户2026-10-04明确tone-map卡顿非高优先级，不能快速解决就后移。暂无快速修复证据，已独立deferred到TASKS末尾；保留成果和实际性能失败，不继续新性能包构建。优先manual Resume/全屏/HDR10及其余既定验收。

- **历史已验收R15**：APKa4188022/lib2203064c/JAR67395d8e实际回读一致；run1791129083503999-hdr10唯一播放，用户“刚才的视频效果没发现问题”一般视觉接受；strictClose真实配置恢复/Player终止/Launcher通过，timeout30000恢复并sleep，无Root live设备工具。两actualconfigure input status0/surface0+1/available1/truncated0，format只尺寸/mime/CSD88B，无打印profile/color/static键，输出transfer3/HDRflag0；不否定CSD/SEI或光学HDR，双参数隔离候选已获独立native build/package审核，color20891/profile12651实际exit0，两个原生产物及JAR内lib逐hash回读通过；均未APK/设备。N4 helperv2实验独审PASS，19独立测试/分析通过，永久rawopen pending缺口保留；页面候选已冻结（page708ec240/test3dcb181f/REPORT0f524ad6），5定向测试/分析通过，独立页面审核REQUEST_CHANGES：缺最终Player终止门禁和Close最终报告，原writer第一轮修正中，未APK或设备。R14同PID/owner Java release与ACK外部关联独审通过，不改原journal、不证明SF资源回收。
- **目标/授权**：LG-H870DS API24 HDR能力检测与demo移植仍进行中。安装和设备实验已授权；未提交或推送。保留其他Darwin及共享修改。
- **历史R13**：APKec526b97/lib7cc6f4ac实际回读一致；人工“比例和HDR亮度都正常”，SF真实1440x720匹配2:1；strictClose通过，timeout30000恢复并sleep。MediaFormat color-transfer3/HDRflag0与系统hal_hdr仍待解释，不宣称光学或静态元数据合规。历史R12 APK40c75b5c，人工完整画面/颜色/流畅通过，HDR亮度未确认、画面比例失败；strictClose已通过，timeout30000恢复并sleep。历史R11 APK57ec4676/lib7cc6f4ac，实际回读一致；原生路径成功但decoder transfer读回bt.1886，HDR显示未证。严格Close已通过并sleep。历史R9：R9 ManualResume APK61081cfeb8d2d6456fe5951898990e09ad700992f1cd277e6a100c19e71af8b1，lib7cc6f4ac/JAR23036e0b；实际pm path-2、整APK/lib回读一致，label lg-p5-manual-resume-r9-20261004。R8 N1为历史验收包。R9重播及安全Recents重测已严格关闭、原timeout30000恢复并sleep，无live设备工具。
- **人工/结构验收**：R3 P5“都正常”涵盖完整画面、颜色、亮度、流畅性。R6默认全屏两轮完成证书，用户确认颜色正常、流畅；完整全屏/无旧叠层/亮度未单独确认。截图黑不作实际手机黑屏结论。
- **R7退出实机**：失败Close run1791115834154231-635312793与Back run1791116054322628-636583140，原startup error/debt保持，真实Session baseline恢复verified、Player termination completed、Launcher；无伪成功certificate。健康run1791116207659969-579525501与1791116478398499-181384416关闭end-certified、无error/debt。Surface最终release ACK未独立观察。
- **Home/Recents**：ManualResume已实现冻结，作者123PASS/独立67PASS、build-only审核通过。R9 Home回原Session paused→唯一ManualResume→10s end-certified（人工transition仍缺）。Recents卡片中心误点系统全部清除、trigger0tap，Root/Scout同XML确认，不能作demo崩溃或通过；旧run cleanup未证。用户要求重播的新run1791121423451177-1005497713完整画面/颜色/亮度/流畅性“都正常”，严格Close通过。安全Recents重测run1791121869088856-575810286 sameSession/唯一Resume10s端点证书通过，人工颜色正常、流畅，严格Close恢复/终止/Launcher通过；完整frame/亮度未明确，Home安全重测已人工确认完整画面/颜色/亮度/流畅性/连续播放并严格Close通过。
- **N1核心**：四core+新增test冻结，REPORT31029ed6/source-manifest91c029cf已全文回读、五SHA核对归档。frozen155PASS/限定分析green/format0changed，全部handles终止。普通Session私有slot不替换，观察仅默认关闭sync边界与既有owner读回，不作设备证明。
- **N1 lab/独审**：lab正式冻结后独审发现完整route与同token原值证据漏判，Lead最终helper ef07786a修正；正式独立终验24PASS/限定分析无问题，REVIEW37626d6d/manifest2a8a53eb构建门PASS，全部handles terminal。原155core/89lab证据与失败反例保留，不混作设备证明。
- **N1构建/外部工具**：R8 build4484/install97669均exit0；run1791118877628450-n1 coldlaunch16589唯一启动、capture94017完成六轮。真实native prepare10061350us失败、configure/open0；同generation1 ordinal2 SDR gpu-next/mediacodec-copy fallback prepare/configure/open各1，options恢复/typed route audit完整。用户画面颜色正常但卡顿。25243唯一Back清理closed/sessionClean/controllerRetired/termination true、debtfalse，SurfaceACK未独立证明。原timeout30000恢复并sleep，无live设备工具。
- **剩余完整范围**：tone-map性能low/deferred；manual Resume/Home连续播放已通过，Recents完整frame/亮度及全屏完整/旧叠层/亮度待补；真实N4负向、demo HDR10时序/亮度、P8.4路由/性能、现代Vulkan回归及独立SurfaceACK。N1真实回退/颜色/cleanup已闭环，流畅性失败仍保留。默认nativeDV门保持unsupported。

- **历史R10收尾**：唯一SystemBack已发送；外部verify-closed观察40s超时，首次Back的cleanup/Launcher未验证；随后同run唤醒/XML唯一Close按钮tap1，外部最终bytes+Launcher验证通过（见History），不覆盖首次超时证据。工具exit1原始回读已保留。恢复screen_off_timeout=30000（读回一致）并发送sleep。R10是历史验收包，原生HDR10信号问题仍高优先级；tone-map性能low/deferred。



- **R18 profile诊断原生成功/人验及关闭**：77869buildexit0、36166installexit0/APK6f3ba27b/libaa5da5bb回读一致；1991launch唯一run1791133554616327，77998capture四samplesexit0。mode2/gate1/applied2/status0输入profile4096、Surface0+1，输出native transfer3/HDRflag1/static25B；无Stopdegradation，真实boundplatformView/nativePQ路由成功，不宣称diagnostic修复或排除race。用户除HDR状态不确定外全部正常、亮度看来可；5184strictCloseexit0/configrestore/termination/Launcher，98594explicitstopparent0child-15，timeout30000恢复/readback/sleep。全部证据R18runtime归档，root全部terminal。R19color同诊断95400buildexit0 APKf24b137f/lib6c8ec17e未安装，下一对照；R17两失败/R18成功提示间歇性，不证明profile因果。

- **R18 profile诊断APK实际构建启动**：Root全文读v8 REVIEWfbec6957，profile审批ef9a4da7/color912a5fc3，reviewmanifestabc267ed；37689实际exit0双check-only、54源/工具/native不变，限定build-only。启动profile R18实际77869，label lg-hdr10-profile-stopdiag-r18-20261005、输出hdr10-session-release-r18-profile-stopdiag；未安装/实机。v8完整资料归档。Root读回手机仍pm-2/R17、timeout30000/Asleep，保存pre-r18-device-state，不预先修改设备；R19color待同诊断串行构建。

- **Stop源码独审通过/v8审批收尾**：Root全文读取REVIEW3d74f2b4，限定PASS_STOP_DIAGNOSTIC_SOURCE_ONLY；39910/61556/96844实际exit0，35+40独立测试/Noissues，sourcehash不变，Flutter释放。保持stop/锁/短路/read次数、原异常和first对象，无URI泄漏；仅新增错误reason，不证明LG实际根因。报告日志归档。v8Reviewer source54filefb779a2f/canonicalcae12d52实际核对通过、52旧源不变，工具/native保持原版本；正式Stop结论已提供，继续双APK精确审批/check-only，未实际build。

- **Stop诊断正式冻结/新源54入场**：Root全文读REPORT2174e4d2并归档，backend4d37df51/test5e2cc89c正式停写，作者68190 35PASS/64159 Noissues/format0/无lockfile变更。原N4 Reviewer正式followup激活独占Flutter源码复审；Root新source54filefb779a2f/canonicalcae12d52，仅更新backend+新增直接测试。HDR10 Reviewer只v8 delta源静审/hostcheck-only，待StopPASS后批准profile R18及color同诊断R19，复用未改变v3/native，不重做旧工具测试，不合native参数。尚未新build/设备，R17仍手机实际包。

- **Stop诊断作者35测试通过/最终runtime报告补全**：原writer68190实际exit0、35/35PASS（含三个具体失败reason、成功两次read、stop/两次read原异常对象与精确次数），analysis64159进行中，尚未freeze或独审通过。N4原Reviewer只读准备诊断独审，禁止并发作者Flutter，待freeze后实际复验。RootSHA核对runtime REVIEWadd2eb58及重新freeze资料并归档，retry现使用最终closed64577ms/22samples/strictClose、人验卡顿HDR未知，原9.216s snapshot保留历史；不再把已有最终证据视为缺失。

- **诊断实写与独立因果报告回读**：Root实际读backend方法已拆原拒绝条件，path/entry非空仍一次read、空/空再secondread、原StateError前缀及安全标量，无URI/延迟/新轮询。独立runtime REVIEW全文回读：现消息只定位outerstop，不是configure错误；profile因果不足，codec flushing在degradation后仅时序假设。报告retry仍保留interim9.216s缺最终证据，已要求补实际闭合归档/人验并重freeze，保留旧snapshot，不扩源码观察API。本轮只待最小诊断定向测试和独审，不改变实际停止/ownership策略。

- **Stop失败诊断最小工作包启动**：Root确认真实captureStoppedBoundaryUnderLock原停止后按短路检查path/entry/secondidentity，现R17泛StateError无法判具体失败项。原writer只获该backend方法及相关production测试诊断权限：保留锁/stop/短路/read次数/StateError前缀，附安全reason/empty/epoch/player标量，禁止URI、轮询延迟清源、策略改变。只诊断不修复、不build/ADB，待实际测试/freeze/独审；原runtimeReviewer继续独立对两次失败证据，不归因profile。此新源码将使旧v7source审批失效，不能沿用旧批准构建新包。

- **R17同包独立重测复现**：原包/lib不变，71527exit0唯一新run1791132667608530-hdr10，14824exit0四samples；1.623s同Stop稳定empty失败→SDR，mode2/gate1/applied2/status0/profile4096/HDRflag1，均Surface0，未native输出。用户“卡顿，HDR无法判断”，未扩frame/比例/颜色接受；69533strictCloseexit0真实恢复/Player终止/Launcher通过，53125explicitstopparentexit0child-15，timeout30000恢复核对/sleep，全部Roothandleterminal。证据归档retryruntime并交Reviewer。确认同包复现，尚未证明profile直接因果；三项实际失败谓词path/entry/identity变化未日志记录，下一需定点诊断，性能仍low。

- **R17真实profile实验及失败链保存**：install27809exit0/launch90620exit0/capture90873exit0，mode2/gate1/applied2/status0、输入profile4096/CSD88B，两次Surface0输出HDRflag1/static25B无color键；native strategy切换在1.451s Stop did not establish a stable empty source，随后SDR gpu-next/mediacodec-copy，sample native判拒绝，未Surface1native配置。profile影响HDRflag已观察，不能把切换失败归因该profile或算显示HDR通过。用户颜色正常但不流畅/HDR无法确认，tone-map性能继续low。XML唯一Close一次后76960exit0clean/errornull/sessionrestore/termination/Launcher通过，74839explicitstop parentexit0child-15，timeout30000恢复/readback/sleep；全部原始与人验归档R17runtime。下步只读追实际Stop稳定空source失败，不先合并profile+color/改默认。

- **R16真实参数/输出及人验完成**：launch35855 exit0唯一run1791132278693947-hdr10；醒屏首次keyguard断言失败、随后原wake读回Awake/ON/keyguardfalse通过才启动。capture首次误用run-anchor文件名未建输出，改实际anchor.json后28641 exit0四samples；不重启播放/观察窗。两configure avctx2/9/16/9/1，dovi_present0，mode1/gate1/applied1/status0/input未截断，实际color6/6/2、CSD88B；两output transfer6(PQ)、standard6/range2/static25B，hdr10-video-playback仍0，MPV gammaPQ。证明输入映射改变了decoder transfer，不证明面板光学HDR。用户“其它都没问题”，完整/2:1/颜色/流畅接受；HDR亮度看起来可、状态仍不确定。唯一XML Close tap后14142 exit0 strict final/session恢复/Player终止/Launcher通过，原errornull，ACKjournal仍unverified。41389 explicitstop parentexit0/child-15，全部Root运行terminal；timeout30000恢复/readback/sleep，证据归档R16 runtime。R17 profile9390实际exit0 APK4289a82c/libaa5da5bb，尚未安装/播放，下一独立对比。

- **R16实际APK完成/R17与安装推进**：31557实际exit0，color R16 APK791c3160/lib6c8ec17e/JAR0a7d8c99，Root实际APK全hash和ZIP内lib回读通过；构建身份/log归档。R17首次命令误写用户目录，mkdir前FileNotFoundError且未Flutter、未产物；正确绝对路径后9390真实profilebuild运行，原失败保留。R16 install-verified实际34164运行，未作已安装/显示接受结论。设备adb devices真实LG在线；尚未R16launch。

- **v7正式双APK构建门通过/R16实际构建启动**：Root全文读REVIEW779c2bc3，最终color审批e90f43aa/profile50add88a，reviewmanifestc7c1b8f2；Reviewer90832 exit0两actual check-only成功、source53/tools未变，N4页/helper精确报告绑定，全部terminal停写。Root按唯一v3启动R16 color Release实际handle31557，output hdr10-session-release-r16-color、label lg-hdr10-input-color-r16-20261005；未安装/播放，R17 profile待R16terminal后串行。正式v7审核材料归档，不扩build-only到设备效果。

- **页面独审最终通过/工具独审terminal通过**：Root全文读N4 REVIEWce845aae，限定PASS_PAGE_EXPERIMENT_SOURCE_ONLY；12+14PASS/analyze14930 exit0，已释放Flutter，原两P1修正、页面真实接线和最终报告原子顺序通过源码/host，不涵盖Androidrename/native处置/有界pending/设备。报告日志归档。HDR10工具Reviewer20435 exit0/5groups19拒绝/mockfinally门通过，TOOLS-REVIEW82e49e4c，source53实际hash/sourcecontract匹配，HDR10start/close/exit byteexact。已告知N4门满足，推进最终双variant APKbuild-only审批，尚未实际build/设备。

- **独立实复验结果取得**：N4 Reviewer实际46620 exit0/12PASS、3627 exit0/14PASS（另补pending startup/重复exit），Root完整读实际test/counterexamples日志；analyze14930原agent尚确认terminal，日志已Noissues6.1s，不擅自判结束/释放Flutter。HDR10 Reviewer20435真实host验证，tool-host.log实际PASS5/refusals19/actualSubprocess0，无source或APKapproval；待原agent确认terminal和冻结review。Root无Flutter/build/设备操作，不提前算实机或审批通过。

- **正式冻结与双独审推进**：v3工具writer停写，Root核对REPORTdf1e327b/artifact1105122e及全部artifact/25fixture SHA一致并归档；N4 page作者最终636f23fa/test3f59d4a0/REPORTv29763bcff，最后26208 12PASS/29446Noissues且无live。N4原Reviewer正式独占Flutter复审；HDR10原Reviewer正式工具host和source53静审，不并发Flutter、不提前APK批准。Root生成精确source53 manifest（file8174c741/canonicalcontract3362b3c9），绑定原48+5依赖/测试，已交审。未APKbuild/设备。

- **工具17反例终验通过/最后页面复验**：v3 writer14640实际exit0，8groups/17拒绝（18为启动前估计，现纠正），全部构建前拒绝、subprocess0/无APKoutput；Root全文读REPORT和host-checks.json。正式工具独审已启动，只读静态暂未阻断，待artifact-manifest最后freeze后host复验，禁止提前APK批准。N4 page最后journal fallback后26208实际exit0、12/12 PASS，analyze29446 running；此前81917分析虽通过不用于覆盖后续改动。未设备/安装。

- **N4新12测试作者通过/v7依赖入场完成**：作者12954实际exit0、12/12 PASS（原35627编译失败、29960两反例失败保留，修正原错误fallback和pending fixture后通过），限定analyze81917 running，未冻结/独立复审。Root完整读取v7只读INTAKE，N4=false普通HDR10 constructor/start/close/exit/2:1静态保持；后续精确source inventory需原48+3production foreign_ownership/hdr_disposal/android_video_controller selector+2tests，等最终pagefreeze。只读intake归档、不作APK批准；v3 18拒绝host测试仍待终态。

- **实际测试阶段启动**：N4 page writer格式后启动flutter test实际35627，Root跨agentpoll返回Unknown process id，已要求原agent继续同handle核对terminal，不把跨agent不可见作完成/重启；原agent随后确认35627编译失败terminal（nullable Future与list的??推断Object）；按显式null分支修正后新test29960 running，原失败保留、不计PASS。Root未并发Flutter。v3 writer启动host14640：真实双native链+toy source/review fixture、subprocess硬禁用、CLI check-only及18拒绝case，无APKoutput。v7只读intake已通过followup正式激活（此前仅send_message未触发idle reviewer，现已纠正）；仍无APK批准或设备结果。

- **N4第一轮页面实写核对**：Root实际读取生产AndroidNativeDvN4PageCloseSequence，顺序awaitstartup/execution、diagnostic/helper close、event cancel、drain，然后最终原子报告，再要求明确termination success才允许pop；失败尝试传播原playerDisposeError/stack。真实页面现已调用该sequence、显式Run结果保留并使用最终journal/finalCloseErrors，不再跳过已有报告。此为活动writer源码核对，未冻结或测试通过；永久pending仍await不伪终止。v3 writer报告6AST通过、无livehandle，尚补host入口拒绝fixtures和正式REPORT。

- **v3真实native预检快照通过**：Root只读import活动builder36a1ce42，实际verify_native分别核对color/profile完整JAR/lib、produced identities、批准/report和所有build outputs通过，5设备脚本与v2逐字一致，前后builderhash相同；未subprocess/Flutter/ADB/建立APK输出。证据lead-native-preflight-snapshot.json保存于hdr10-apk-v3-intake。writer仍补host拒绝反例/正式freeze，不能把此快照作source/tool独审或APK批准。N4页面close sequence已开始实写，尚未作者测试/冻结。

- **双参数实机对比验收计划落盘**：Lead保存device-comparison-plan.md于hdr10-input-parameters-native-results-v1，明确固定PQ SHA、每variant独立完整身份/唯一run/实际avctx门禁与输入键/输出/2:1人工画质/严格Close/外部owner ACK。gate0不当setter成功，applied不当framework接受，CSD长度不当SEI缺失，系统HDR不当光学校准。仅后续执行计划，当前无新APK或设备接受结果；tone-map继续low。

- **Lead构建后archive实字节核对**：Root独立read/hash两候选libavcodec.a各483member，与R15原archive比较均只有mediacodecdec_common.o改变；新lead-archive-recheck.json落归档。此前JAR逐entry实核对6非target bytes/selectedmetadata一致，进一步确认两variant均保持PS及其余FFmpeg成员原字节。仅native产品范围，不证明HDR10参数被framework接受；N4修正和v3工具由各唯一writer进行中，无Root构建/设备会话。

- **HDR10 APK新源入场核对**：Root实际比对v6批准48source，目前仅page变化（旧22475cbe→708ec240），其余47相同；结果保存hdr10-apk-v3-intake/prior-source-drift.json。此为活动writer期间只读快照，不作冻结manifest/审批。原Reviewer仅准备v7只读HDR10(N4=false)启动/挂载/strictClose和新增import依赖入场，等N4修正和v3工具freeze后正式APK源审；未运行Flutter/build/ADB。

- **N4页面独审两P1实复现/修正启动**：Root全文读取REVIEW97c1d48b及反例日志，Reviewer提取真实page Close/exit方法运行Plain Dart exit0，复现Player termination失败仍pop、已有Run报告缺最终diagnostic/event.cancel错误。helperv2限定PASS不变。已归档n4-foreign-ownership-page-review-v1，原page writer独占修正终止门禁与最终原子报告/落盘失败保持退出，补真实页面close链反例；不得强造有界pending清理或覆盖原owner error/debt。第一轮修正中，无APK/ADB。

- **双参数真实原生构建完成**：color20891与profile12651实际exit0；Root逐项核对两build-identity.outputs及JAR内lib哈希一致。color JAR0a7d8c99/lib6c8ec17e；profile JAR12951151/libaa5da5bb，基于R15 JAR67395d8e，独立native build/package限定成功。审批、身份、build.log归档hdr10-input-parameters-native-results-v1。未APK/安装/运行，不证明setter实际生效。原writer仅新v3工具绑定双variant/精确产物准备，N4页面独审发现退出终止与最终落盘两风险，待正式修正；旧v6APK审批不复用到变动页面。

- **双参数独审通过/实际color构建启动**：Root全文读取REVIEWf3419601和color精确审批；正式native build/package两variant限定PASS。独立91381五组PASS/90857终验通过；7834源header路径失败保留不计通过。Root启动color prepare-build实际handle20891，当前running，profile待串行；审批不涵盖APK/默认/实机。N4页面作者正式冻结page708ec240/test3dcb181f/REPORT0f524ad6，5定向测试PASS、analyze/format/diff通过，无liveFlutter；已交原N4 Reviewer独立页面范围审查。

- **实际验证进入收尾**：Root实际读N4 page transport新5test，覆盖互斥准入/同Player exactURI rawopen/异身份拒绝/未accepted拒绝/Close同步封锁；writer报告本轮5PASS、分析仍收尾，不扩成完整页面生命周期或设备证明。参数Reviewer7834实际独立host验证running，subprocess禁用、真实gate/inventory/archive/JAR/审批拒绝，待同handle终态才最终两个审批；Root未运行候选build。

- **N4同步关闭保护实写/设备库存复核**：Root实际读page close入口已同步_nativeDvN4Closing=true、_autoPlayerDisposed=true并transport.stopAdmission后才awaitstartup，修正方向已落实；host反例/整页分析尚待作者，不宣称通过。Root adb devices -l实际仅LGH870DS42e27764在线，现代Vulkan设备回归当前无其他设备，保留该单项输入缺口，不阻塞N4/HDR10可推进工作。参数Reviewer实际running终审，未newbuild。

- **双参数候选正式冻结交独审**：Root实际terminal/finalpostcheck、REPORT0baa1ec6/artifactf802413e完整SHA核对相同；inputs32df6174/prep9d93069d，5080input/691headers/483members/twoplans全一致，37198/90224exit0、8host门、两build不存在。材料已归档（不拷真实header symlinks），交Reviewer正式两variant独审，scope仅nativebuild/package，不批准APK/默认行为/实机。R15仍当前设备包，N4page未冻结。

- **候选8host门通过/页面退出源审**：nativewriter37198prepareexit0，hostchecks同步exit0八项（含17未知/DV/HLG gate反例与variant/hash拒绝）已落，final90224实际read/hash running，只验证无native工具。Root实际读N4cached close/legacy fallback不递归runner，但closing在awaitstartup后才置，反馈需入口同步拒绝新rawopen，并补startup/ready/Close交错host反例；候选仍作者可改，未冻结/未正式通过。

- **P8.4实际设备字节校验完成**：92761同handle exit0，exec-out完整回读1232790317B、SHA7626cac28819ffd1377a712b56c7cc4bbf8677f5db4b39fb0c83f92e58d74443与固定host一致，elapsed307.837s；device唯一/data/local/tmp/media-kit-p84-7626cac2.mp4已可用于后续普通Session候选。只素材验收、不播放/HDR证明，原始input/push/readback verification已归档。Root全文读参数候选REPORT/official映射限制，prepare37198exit0待host门及冻结，不把draft证据算PASS。

- **参数候选隔离门源审/回读live复核**：Root实际读variant审批字段和build流程，color/profile独立OUT、精确variant/hash、只common archive member允许改变、postchecks保留；尚无正式冻结报告，不native。ReviewerWIP无静态阻断但明确DOVI_CONF缺失非独立无RPU证明、appliedmode非framework接受。P8.4 verifier92761同handlepoll running，实际ps确认Python76886+adb76887均live约3:24，不因观察未返回重启或认失败。

- **N4 page实接线源审**：Root实际读新N4PageTransport/late Session创建，独立flag要求fixedP5诊断且N1互斥，真实helper/session bind接线已落，仍作者未冻结阶段。反馈ready不可遗留旧generation许可、未执行Close仍cached一次清理、报告失败不得伪退出；Root未改writer源。参数候选prep输入/commands/lookup audit已实际落但尚无正式REPORT/审批。P8.4整回读92761再次确认running，等同handle不重读或重推。

- **双mode源已落/真实prepare live**：Root实际读新diagnostic.patch，mode0默认无setter，mode1三个existingmapping setters，mode2仅Androidprofile0x1000；configure前avctx五scalar与真实DOVI_CONF gate/applied日志，selection既有代码不变。writer37198实际prepare running，独立build-color/build-profile且variant新审批，未经审核不compile；交Reviewer只读WIP不审批。N4page实际新flag/helper绑定字段已落，仍作者实施阶段。P8.4回读92761同handle仍running，未重启、不用中间字节作验证。

- **P8.4传输实际完成/回读校验启动**：77103同handle exit0，固定1232790317B已push唯一media-kit-p84-7626cac2.mp4；Root编写streaming exec-out整byte/hash核对器（不依赖设备缺失sha256sum），92761实际running，无播放/新APK。先前传输期间实际文件909180928B为中间状态，不当完整证据；最终verified结果仍待该handle。

- **10-05延续/P8.4素材传入启动**：日期已跨10-05，继续同topic/goal不重启历史实验。nativewriter真实读R15stage链且将生成两modecopies；N4writer已开始page接线，两者无liveFlutter/native。Root实际LG /data空闲48277640KiB，目标media-kit-p84-7626cac2.mp4不存在，唯一host固定1232790317B素材push77103实际running；不覆盖现有文件、未播放，传输成功后仍须整byte/hash校验，不替代路由或显示验收。

- **N4修正版page方案确认**：writer修正为独立flag/run且与N1/performance/lifecycle/HDR10/simulated/sourcechanging互斥，真实P5正常mounted；独立JSON和单次按钮、真实回调late Session→bind→events→open、settled后cachedclose避免double dispose。Lead批准唯一pagewriter实施及定向host验证，未经独审不APK/ADB。nativewriter准备严格HEVC/Main10/PQ/BT2020NCL/limited且真实DOVI_CONF排除的隔离模式1颜色与模式2profile，同configure前记录scalar/gate/applied；mode0只保留诊断、不setter，不证明厂商接受或修复。

- **HDR10双隔离候选/N4准入冲突修正**：nativewriter只读核对sourcecodecpar/probe→avctx颜色/profile真实传递，AndroidAPI24 constants标准6/PQ6/limited2/Main10HDR10 profile4096（FFmpegMain10为2）。Lead授权专属copies双实验仅color或仅Androidprofile，保持codec selection2，配置前记录真实avctx并严格PQ/BT2020NCL/limited/Main10 gate，默认macro0、不改CSD/static/nativeDV，prepare后独审才compile。N4writer方案原要求N1flag，Root实际见N1 init令videoMounted=false会制造preparetimeout，拒绝此准入；要求N4与N1互斥、固定P5真实正常挂载后accepted、独立callbacks/单次rawopen/pending无成功退出。先修方案再关键page。

- **N4页面下一实施包**：Root全文读v2REVIEW3df0d3e6，真实coordinator disposal invocationnull/ownerplan generation与helper契约相符；独立16+3反例19PASS/analyze，永久pending限实验明确。归档后交原writer页面N4默认falseflag/真实回调bind/唯一samePlayer rawopen按钮/atomic原错债务报告及settled后退出方案，先给Lead计划再关键写入。page单writer，helperv2冻结不改，HDR10分支/普通mode保持；不build/ADB或假能力。Root并行native输入参数只读方案仍待返回。

- **R15人工反馈与输入修正方案分派**：用户直接回答“刚才的视频效果没发现问题”，记录R15一般视觉接受/无明显问题，不拆成绝对亮度或逐项量化通过。Root实际核对mediacodecdec.c input仅mime/width/height，canonical无color/profile setters；交nativewriter只读研究真实avctx色彩/profile来源与Android映射，方案color-only/profile-only分离因果、PQ/BT2020/Main10真实gate、默认关闭隔离，不复制Java static25B/CSD、不假设toString缺键即SEI缺失，暂不写/build/ADB。

- **R15实际configure输入与strictClose完成**：首次wake即时assert未过，随后只读复核Awake/ON/unlocked通过，未提前launch；5710唯一run1791129083503999-hdr10原120s，63338四journalexit0。两actual input rows均OMX.qcom HEVC、status0/available1/truncated0，surface_present0与1，input仅height1920/width3840/mimevideohevc/CSD88B，toString无profile/color/static字段；不能据此否定CSD/SEI内容。对照JavaPQ input profile4096/transfer6为下一修正线索，未改format。33054actualfinalbytes+Launcher cleantrue/errornull，CloseXMLtap1；14882全Close日志显式stop terminal-15，timeout30000恢复/sleep，所有Root运行终态。人工R15待回。N4v2独审限定PASS_HELPER_EXPERIMENT_ONLY，独立16+3=19PASS/analyze，永久rawopen pending gap保留，未page/device。

- **R15实际build/install完成**：88796actual exit0 APKa41880225019b5fb801aa9d9ec8e97ae7c391a23140ea5dd7a2810baa53767d8/lib2203064c，65860install exit0实际pm path-2/APK与lib回读一致，label r15；未新播放。Flutter已交N4v2Reviewer独立验证。

- **v6批准/R15实际build启动与N4v2冻结**：Root全文读v6REVIEW17d2a4d5/buildapproval53650a25，37PASS/analyze及纯formatter delta精确复现、终check-only通过；48源仅两变/tools/native未变。N4writer16PASS/analyze/format0changed并释放，v2helperddf66a96/test7ae81855冻结交原Reviewer只读先查，永久rawopen pending的cleanupgap保留。Root独占实际R15build88796启动，仍running，不重启/未安装。

- **R15配置输入观察协议细化**：Root核对page无额外过滤，player.stream.log已原样转发journal；新增input分支与native emitter一致。下一观察保留每个实际configure的codec/mime/Surface/status/available/truncated和输入format原文，与output/JavaPQ对照，不把缺失toString键当CSD/SEI不存在、不注入元数据或猜Surface代。已记录R15-OBSERVATION，原120s/唯一coldlaunch/30s人工/完整Close日志不变，等待v6冻结批准及Flutter资源；未启动新build/run。

- **事实源旧状态清理/v6实际测试live**：Root同步TASKS当前R14实播/strictClose/人工待回、native/APK实际完成与v6input采集增量，替换先前未启动/尚未native/未APK过期描述。R14 JavaACK独立关联限定通过，P5与失败分支对应ACK不扩大。Reviewer20204为实际live Flutter定向测试，等待同handle结果，不重复启动。

- **R14 ACK独立关联通过/Flutter移交v6**：Root全文读R14-ACK-REVIEW，Reviewer核对package PID32154启动→handle545864357968/wid1050790创建→同owner/surfacegen1样本→23:40:39.990 phase1 released→23:40:40.010 phase2 acknowledged及随后同handle销毁。外部Java二阶段ACK关联通过，原journal不改、不宣称SF资源回收/显示/input；已归档并更新ledger。v6两文件静态无阻断，余46源/page/tools/JAR一致。N4writer本轮13PASS/1cancel夹具失败且所有handles终态，授权v6 Reviewer独占短test/analyze；writer继续修夹具不Flutter。

- **R14原始证据归档与台账同步**：Root归档实际APK/install/anchor/fresh/close/唯一tap/完整capture起止receipt，另保存PID32154的12条原始Surface/ref日志（保留host完整ring，不移旧run日志冒充）。实际final journal两outputformat仍copy无颜色/native BT2020-transfer3-range2-HDRflag0/static25B；input未记录，人工待回。ledger更新R14、strictClose已通过/ACK交叉关联待独审，不修改原journal unverified或宣布HDR通过。

- **R14配置日志缺口定位/被动采集修正**：Root实际源码显示recordCodecFormatLog只接受Output MediaFormat，因而新native输入tag被journal过滤；rawlogcat无该tag不能证明未configure。仅HDR10 helper/test新增精确hdr10_config_input event=configure分支，原样bounded保存为codec-input-format-log，并标CSD/SEI/attempt/Surface/panel未证；page/native/JAR/策略不改。新增原文/无关tag拒绝hosttest尚未跑（N4独占Flutter），交Reviewer先只读增量v6和R14 same-runACK复核，未经新批准不build。

- **R14实播/关闭日志补齐**：79163unique run1791128381893167-hdr10原120s，80919四journal exit0，nativeSurface1440x720/sys hal_hdr。22708从launch前至Close后持续hostlog，90086actualfinalbytes+Launcher cleantrue/errornull；同PID32154/owner(handle545864357968,generation2,viewId0,surfaceGeneration1,wid1050790)在23:40:39.990 deleteGlobalObjectRef1050790+releaseSurface released，23:40:40.010 acknowledgeSurfaceRelease acknowledged，随后surfaceDestroyed wid0。这是same-run交叉关联ACK证据，journal自身仍标unverified，未改旧报告；可交独立证据审核。配置输入hdr10_config_input未进入rawlog，实际取证尚缺，需查lab订阅过滤是否丢弃，不宣称无configure。唯一Close实tap1，timeout30000读回恢复/sleep，22708显式stop后terminal-15，所有root runtimehandles terminal。R14人工回答待用户，未通过显示验收。

- **R14实际构建安装完成**：29840 exit0 APK45cd05e46ec1ceab78e8b87d7865d323cfd6bd3bd17408010310b99d1015537e/lib2203064c/JAR67395d8e；75853install exit0，实际pm path-1、整APK/lib回读一致，label lg-hdr10-config-input-r14-20261004。未启动新播放/未人工验收。Flutter已归还N4writer；下一unique coldlaunch配合完整Close窗口logcapture。

- **R14实际APK构建启动**：v5 REVIEW7f2b7578/buildapproval057a44a3全文读取，48sources与v4同字节、实际candidateJAR/483members/PS保留、8drift拒绝通过，仅build门。N4writer确认无liveFlutter并移交Root，唯一R14build29840已启动label lg-hdr10-config-input-r14-20261004，poll仍running，日志实际JAR67395d8e；尚未APK身份/安装/新播放，N4新文件未接page且不属48sources。

- **R14前置设备状态实际复核**：Root只读ADB确认LG online、pm path /data/app/com.example.media_kit_hdr_lab-2/base.apk、timeout30000；exec-out实际原journal同R13 run1791126236837253-hdr10，closed/sessionRestorationVerified/playerTerminated=true、debt=false，label r13。未唤醒/新启动/播放，下一候选唯一coldlaunch已有前序cleanup条件。v5 APK审核目录已有candidate/tool/source manifest及host日志，正式批准尚未读取或执行。

- **N4正式REQUEST_CHANGES修正授权**：Root全文读REVIEWc0b88883（manifest34009037），原8+2反例10PASS证明两误判、analyze无问题，27345/26523exit0且Flutter释放。已交原writer第一轮修正：绑定同Session/gen disposal stop entered→failed原错，拒绝generic debt/stop returned/reset/options restore误接受；callback时同步foreign cutoff，覆盖rawopen返回前/快照等待期间所有configure/open/prepare/rebuild。另要求cancel异常仍finally Player终止，rawopen挂起的有界方案不可伪settled/破坏锁。仅helper/test，未page/device。v2 APK审核继续，不重复native已完成结论。

- **native构建/JAR实成与N4审核拒绝**：71565同handle exit0，isolated common compile/archive replace/link/strip/package完成，产物JAR67395d8e/lib2203064c，Root实际全hash与ZIP逐entry核验6个非target未变。identity/log已归档，输入/原基线postcheck通过；仅产物成功，不是configure-input/显示证明。已交Reviewer审核v2 APK精确新JAR/nativeReview信任衔接、R13 sources/defines，N4 Reviewer独占Flutter不并发。N4独立10fixture（原8+两反例）实复现P1：unrelated disposal debt无stop失败仍accepted；foreign FILE_LOADED后rawopen返回前configure entered漏判。待REQUEST_CHANGES正式冻结，writer先只读修正方案，不接page/device。

- **native批准并实际构建启动**：Root全文读取REVIEW31e7471f与精确native-build-approval，限定PASS_HDR10_CONFIG_INPUT_NATIVE_BUILD_PACKAGE；不涵盖APK/device/CSD/Surface/显示。已按唯一隔离脚本启动native build handle71565，poll仍running，尚无产物成功，不重启。N4独审提出host证据predicate可能未要求stop失败边界及foreign事件记录窗口，fixture验证中，不擅自修改候选或判通过。

- **N4冻结独审开始**：Root实际核对helper d5a4d6a6/test af960359完整SHA与作者冻结相同、全文读REPORT421337f5并归档；作者8/8hosttransportStub与限定Noissues、Flutter释放。已交独立Reviewer仅helper/test/fixture验证，独占Flutter，禁止page/ADB/native；不批准实机或宣称stop-issued/SurfaceACK/旧owner恢复。HDR10 native正式approval文件仍待Reviewer落盘，未构建。

- **独立host终验通过待审批文件**：Reviewer82541实际exit0，五组fullinventory/artifact、command/member/patch、build/package错误审批/prepare拒绝、递归headers/fixture漂移、baseline JAR reader检查PASS。原5432 loader失败保留。无native/package/Flutter/ADB，candidate build目录仍不存在，正式approval/manifest正在写；Root准备收到精确文件后全文核对再独占native构建。TASKS同步当前工作并修正旧R11为历史记录。

- **APK v2工具草稿/N4反例**：Root在新的hdr10-session-device-tools-v2复制旧工具，builder改为固定隔离candidate JAR并要求nativeCandidate jar/lib/identity与独审report精确SHA，build后重验；原v1不改、AST通过，未native产物/审批/Flutter执行，仍需独立审核。N4八项test已实际落盘，包含early stream error与close admission；writer报告第8项bounds fixture顺序失败已保留并修正，正重跑，不宣称全通过或实机通过。

- **native正式冻结/P8.4准备**：Root四完整SHA核对writer冻结集一致（REPORT3db3e00b/artifactf9d949ef/inputscd262bb8/prep0f6242f0），8host边界PASS、native未执行；已交Reviewer正式独审并归档材料，不含691实际symlink副本。P8.4 Scout本轮host SHA7626cac2/HEVCMain10-HLG-DV8compat4确认；LG真实SDK24/display[2,1]无HLG，当前源码预计direct displayLacksTransfer、convert SDK<28硬门、默认SDR回退。此为预测非实机验收；R13 HDR10专用包不适用，需普通Session候选/设备字节核对，不以回退冒称P8.4 HDR，性能low。

- **header修正实质准备通过**：Writer同handle36092实际exit0；Root回读quoted-include-audit与inputs-manifest，60files/197resolvedEdges/unresolved=[]，4373输入与483archive members。新增691隔离header symlinks，不改compile argv；最终host65511验证symlink target/membership拒绝尚在运行，未native compile、尚无冻结审批。

- **日志工具host边界通过**：Root用进程stub验证deadline、explicit-stop、child-exited三种收尾，均terminal且有started/final receipt；无ADB执行，不作为Surface或播放证明。N4源码实际出现closingRequested同步门，异步错误反例仍由writer验证；native隔离header链接已实际生成，最终prepare结果/冻结尚待回报。

- **Close日志工具与头文件准备**：Root新增独立surface-close-log-capture-v1/capture.py，exec-out只读日志直写、唯一目录、开始/结束/PID记录、stop文件及最多180s终止并reap；AST通过但未设备执行，不修改播放原120s。准备从launch前覆盖至strictClose后，避免R13缺26.5s窗口。nativewriter已接入隔离header symlink与递归lookup审计，36092实际prepare running，无native过程；待同handle终态、host复验与新冻结。

- **native quoted-include缺口与APK衔接**：Writer发现复制common.c后同目录quoted headers搜索缺口；Lead接受只在隔离目录建立冻结canonical headers只读symlink、绑定路径/target/SHA/membership及实际.d解析的修正方向，不改原-I参数，待新冻结独审。Reviewer初步确认被动日志/归档替换/JAR差分设计无静态阻断，但不作最终批准。旧APK builder硬钉旧JAR，不可复用其审批替新库；已记录APK-CONTRACT，待候选native产物成功后另建精确v2工具与审批，保留R13布局/普通Session/defines。

- **Lead源审增量**：实际回读native REPORT及7项host-checks，均仅prepare/admission边界通过，native未执行；独审继续，精确冻结待writer确认。Root只读N4 execute/close实现，提出两项需验证：rawopen尚pending时FILE_LOADED stream error不可形成未处理Future错误；close开始后不得再新execute入场。已反馈writer补反例，尚不声明缺陷复现或测试通过。

- **并行准备范围**：N4新helper现已实际落盘，Root只读首版并要求先绑定Session/订阅再open，补重复/异源绑定与callback乱序反例；writer独占修改和Flutter。native副本由既有Reviewer只读预审，最终REPORT/冻结与拒绝门检查尚待交接，不compile。P8.4交既有Scout窄只读定位固定素材/实际HLG门禁/普通Session验收入口，无设备或性能操作。

- **诊断准备与台账同步**：native prepare首次54095因目录排序比较不一致exit1，原始失败保留prepare-attempt-1；统一排序后23452真实exit0，冻结3682输入与483个libavcodec成员、基线重读一致，nativeExecuted=false，尚待host拒绝门/argv-delta与独立审核。N4第一版新helper已落盘，typed配对、锁内快照/锁外epoch观察、实际dispose及finally Player终止待编译与正反例验证，未page接入或设备通过。Root同步lg-current-test-ledger的R12/R13人工维度、R13输出格式与剩余验收项，未扩大人工接受范围。

- **Surface ACK观测缺口已定位**：只读Scout核对现有协议，ReleaseSurface先真实删除JNI global ref，ReleaseSurfaceOwner随后返回true并记录acknowledged；surfaceDestroyed、Session/Player dispose返回不等于该ACK。R13日志结束于23:04:43.097，而final约23:05:09.558，缺约26.5秒退出窗口；owner五元组(handle=545850914896, controllerGeneration=2, viewId=0, surfaceGeneration=1, wid=1050790)。已见delete ref2099370不属于此wid，不补作成功证据。下一次唯一run必须在Close前启动exec-out logcat并覆盖Close完成后，按same-run五元身份交叉核对deleteGlobalObjectRef、releaseSurface released及acknowledgeSurfaceRelease acknowledged；Java日志只有surfaceGeneration/wid，完整身份从同run Session boundOutput关联。无需先改释放行为；现阶段仍未验证Surface最终ACK。

- **native基线/N4接口推进**：Root实际核验defaultPS sourceManifest无漂移、lib/JAR与R13一致，libavcodec f0efd426/libavformat38f33da6/common.oed0dc469、archive common member唯一；preflight已归档。nativewriter提出隔离prepare/build/package门+configure前只读format capture、configure后有界INFO/status，未经独审不compile。N4 writer接口方向确认：真实consumerValidated+RouteApplied gate、锁内端点/锁外FOREIGN FILE_LOADED、唯一sameP5 rawopen新entryepoch；实际Sessiondispose report/coordinator原错/选项foreign读回，不人工restore；最后Playerterminate不清旧ownerdebt，stopissued缺观测明确gap。只新helper/test，未page接入/未设备。RootpostClose过滤log未取得release ACK，保持未证；Scout只读查既有释放观测。

- **后续实施分派**：native输入diag writer仅拥有hdr10-config-input-diag-v1独立副本/脚本/manifest，不改canonical、不nativebuild/ADB，准备交独审。N4 helper新writer仅拥有新foreign_ownership helper/test，不改page/库；Lead选择同已byteverified P5 URI rawopen新entry/epoch，避免SDR格式变量；真实accepted同Session/Player gate、foreign FILE_LOADED、dispose拒stop/restore及原error/debt/最后Player终止边界须逐项记录。任何缺少stopissued原生观测保留gap，不伪造。N4writer独占Flutter定向host验证；N4未接page/未实机，不算通过。

- **R13比例/HDR亮度人工通过与严格Close**：88315build/94398install实际APKec526b97/lib7cc6f4ac，59879run1791126236837253-hdr10原120s；66073journal四采样exit0、25883logcat50s终止。SF native Surface真实size1440x720、buffer3840x1920，较R12/R11 1440x1232消除拉伸；用户“比例和HDR亮度都正常”，人工通过，绝对亮度/合规未测；颜色/流畅明确回答在R12，不擅自扩大本次答案。native输出color-transfer3/range2/BT2020/HDRflag0/static25B仍复现，输入配置缺口独立留存。47761唯一XMLClose后外部finalbytes+Launcher cleantrue/errornull，独立SurfaceACK未证；timeout30000读回恢复并sleep。

- **v4比例独审通过/R13构建中**：Root全文回读REVIEW70ae294c/approvale8ec6fe0，3actualFlutterlayoutPASS/Noissues，52307/62344terminal/Flutter释放。仅page22475cbe变化，其余47源/tools/JAR不变，Android比例仍待设备。88315R13构建启动label lg-hdr10-session-r13-20261004。Scout输入格式diag-only native构建准备已由Root记录input-format-diagnostic-plan，未改canonical native源码/未构建新JAR。

- **R12实际格式/人工/清理**：31579build与8396install exit0，实际APK40c75b5c/lib7cc6f4ac回读一致；设备sha256sum缺exit127，39485完整76438009bytes/hash3068be37重新校验18.81s通过。60466唯一run1791125754262939-hdr10原120s，52287四journalexit0，80455logcat50s结束。raw native输出copy无颜色字段/hdr10-video-playback0/static25B，embed color-standard6/color-transfer3/range2/hdr10-video-playback0/static25B；system22:55:56.378hal_hdr。无configure-input证据，不臆造25B内容。用户完整/颜色/流畅通过，HDR亮度不能完全判断，画面比例不对=失败。24593唯一XMLClose按钮后实际finalbytes+Launcher清理通过errornull，SurfaceACK未证；timeout30000恢复sleep。
- **R12比例修复候选（未构建）**：仅固定3840x1920诊断页，用Center+AspectRatio2.0限制viewport，HdrVideo显式aspectRatio2.0，避免Expanded把Surface填满非2:1区域；不改普通Session/native库/其他素材布局。59500限定analyze终态待回读/独审，v3旧源审批不能用于此新源。

- **v3审核通过/R12构建启动**：Root全文回读REVIEW7f6af89a/approval94cc192c，独立36PASS/Noissues、10666/15106exit0/Flutter释放；精确48源及tools/JAR冻结。31579实际R12构建启动label lg-hdr10-session-r12-20261004，尚未安装。详细日志instrumentation会影响时序/性能可比性，不作为性能基线。

- **v3独立36PASS/分析live**：Reviewer10666已exit0（34helper+2实际Close/listener提取集成），cancel抛原错仍Session/Player真实stub清理并finallynull，stream.addError实际onError捕获；均hosttransport边界，非Android实机。唯一分析15106确认live，尚未冻结审批，不构建。Root准备R12原120s/source-bound/PID+format+人工/strictClose观察计划，手机online且上一R11strictClose完成。

- **MediaFormat v3审核中/异常边界修正**：Root将日志subscription.cancel异常保留recordError后继续Session/Player真实清理，finally清空订阅；新增logstream onError显式保留错误避免未处理传播。最终page0f51bf1c/helper2fcbf28f/testeaa4efae交Reviewer，Root停止产品写入/Flutter给Reviewer。host反例不宣称原生设备复现。Scout验证R11JAR manifest与当前FFmpeg common.c SHA精确一致；INFO输出格式日志是实际output读回，不能反推成功configure-input。

- **R11系统HDR证据补读/下一取证增量**：实际logcat22:41:05.726 SDM Setting HDR color mode=hal_hdr，后续LIBHDR_TM/HWCToneMapper；与sameappPID28541原生重建邻近，支持系统HDR处理但非正确像素/人工亮度证明。bt.1886 readback不能单独推翻HDR激活。新lab-only HDR10 Player logLevel v，开播前订阅既有log stream、仅有界保存Output MediaFormat changed原文，关闭在awaitstartup后cancel订阅；其余路径loglevel不变，无native库/策略/元数据注入改动。helper34PASS，首次analyze一项braces已修，最终限定Noissues待回读/独审。新三源尚未构建/安装，v2审批不适用于新源。

- **R11取证/严格Close通过**：80337buildexit0，50186install实际整APK/lib回读一致APK57ec4676/lib7cc6f4ac；52684唯一fresh run1791124863538697-hdr10原120s。66185 exec-out logcat实际PID28541采集50s后terminated-15/父exit0；79759四rawjournalexit0。actual baseLayerDirect/platformView/mediacodec_embed/mediacodec，无degradation、R10回退未复现；初Texture识别PQ，但原生decoder gamma变bt.1886（BT2020），nativeHdr10Configurationfalse，不能宣布HDR通过。SF保存HWC3840x1920厂商buffer但无dataspace/HDRmetadata字段，不能作PQ激活证明。无人工验收。UI唯一Close按钮tap1，9020外部finalbytes+Launcher cleanuptrue/errornull，SurfaceACK仍缺。timeout30000恢复并sleep。Scout只读查MediaCodec颜色输出与原生探针对照。

- **R11增量审核通过/构建中**：v2 REVIEW06bf0324/buildapproval77207ff5，Root全文回读。独立helper33+listener2PASS、三源Noissues、全部1754/91024/4437exit0/Flutter释放。仅三源变化，其余45源及tools/JAR与v1一致；精确新48源审批。80337构建已启动，label lg-hdr10-session-r11-20261004；未安装/播放。R10已同runClose验证清理，不再阻塞下一轮唯一冷启动。

- **R10实际Close补验通过**：唤醒后XML确认仍在同run1791123856641696-hdr10页面，唯一可点击Close & exit bounds[48,2432][541,2624]，Root单次tap(294,2528)，26392外部verify-closed exit0，cleanupVerifiedtrue/原errornull/实际最终bytes+Launcher。原Back未完成记录保留；不重启、不延长原播放窗口、不新增人工播放通过。Surface最终release ACK仍未证。timeout30000读回恢复并sleep。新event journal增量独审进行，未构建。

- **用户要求长期可检索经验已沉淀**：去设备serial/项目信息的方法写入长期库memory/2026/2026-10-04__lg-logcat-exec-out.md，INDEX active，关键词LG/G6/Android/API24/adb/logcat/exec-out/ODM；包含可用命令、开关恢复、新marker证据和因果未证边界。原始设备证据仍留本项目。未提交。

- **logcat实测读取恢复**：按用户LG开关线索测试main/system/events0→1，服务stopped→running，但shell logcat含--help仍空；exec-out /system/bin/logcat可读help/buffer/WWTEST。恢复三属性0后服务stopped，exec-out仍读到新restored-zero-control日志，因此无需保持厂商日志服务开启。未测开启前exec-out，不能排除一次启动影响；准确transport/ROM根因未证。原值恢复，无root/reboot/清空日志/radio改动。证据logcat-enable-v1/REPORT.md。
- **R10后诊断增量（未构建）**：HDR10 journal新增被动public HdrDegradedEvent逐条记录，保留最初failure诊断，不被最终decoder report覆盖；普通Session路由/解码行为不改。三源format0changed、helper33PASS、限定analyze Noissues。旧R10冻结审批只适用于旧源，新源尚待审核/构建；未安装新包。

- **R10 HDR10 实机/人工与优先级**：APK e299d6388b4eacba0bf7063bd6db04584b9feccfae6054f66879626ebdbd8061 实际安装回读一致；run1791123856641696-hdr10。decoder识别HEVC/PQ/BT2020；prediction原生baseLayerDirect，但actual toneMapSdr/Texture/gpu-next/mediacodec-copy，degradeReason unsupportedStrategy，diagnostic decoder review mismatch persisted after rebuild。原生HDR10未通过，不据此推翻设备HDR能力。用户“画面完整、颜色正常，不流畅”，亮度未确认；明确HDR10 tone-map流畅度也列low/deferred，与P5一起后移TASKS末尾，暂不性能修复。

- **HDR10正式独审PASS/R10构建启动**：REVIEWca52edb1/manifestd7c9dd10/buildapprovalc2899461 Root全文读，独立100PASS/limitedNoissues、84750/36726terminal/Flutterreleased。48源/alltools/dependency精确build-only PASS，不作deviceacceptance。正式批准脚本已通过本身review/tools/source/JAR门，70683R10build实际live，label lg-hdr10-session-r10-20261004；未完成APK或安装/播放。审核材料归档。

- **N4正式只读报告回读归档**：REPORTa39da38b Root读，N4=已accepted nativeSession后samePlayer独立rawopen foreign FILE_LOADED、Sessionserial不变→真实dispose拒绝stop/restore并保留原ownererror/debt；不是retry/fallback。现无lab入口，普通Session切源与N1不能代替。核心已有真实owner/stop前门/lastDisposeReport路径；最小候选优先同已验证P5URI新entry/epoch，避免同时引入SDR route变化，但正式实施仍排HDR10后，必须实际外来entry及stop/options/debt/最终Playertermination取证。未产品修改/设备。

- **HDR10独审实际工具终态/限定分析通过**：Reviewer实际poll84750exit0/100PASS，36726limitedanalyzeexit0，27作者artifacts/48source/alltools核对一致。独立strictanchor有效+7拒绝actual通过，verifyclosedmock3同hash绑定。正在formalreview/source/tools gate收口，无新阻断，不构建或设备。LG inventory在线，现代Vulkan设备仍缺。

- **HDR10独立100PASS日志回读**：Reviewer84750实际4pageclose/exit提取集成+32helper+64R9life/page，Root回读independent-tests最终100PASS。actual退出方法主体及stubtransport/extractionhash保留；正式handle终态/分析/最终buildgate报告待Reviewer。48sources/tool/dependency intake一致，未新build或设备操作。

- **HDR10正式作者报告全文回读归档**：REPORT86e4a4e6 Root全文已读/hash核对，三源manifest01fde2db与artifact583714d0/toolstatus全终态交接归档。明确普通Session/无假hint、locked同代baseline/sample、跨sample身份门、atomiccanonical、finalsavedclosed需外部读回、startup error清理debt区分。Reviewer纳入正式冻结实际验证，Root源/tools/draft不再改动；无新build/device。

- **HDR10独审期间后续N4只读准备**：Root核对HDR10专用Close Semantics hdr10-session-action:close-and-exit与Back同_exit入口；可唯一SystemBack+verify-closed，不需要沿用P5actionlocator。HDR10源码/tools保持冻结等待独审，手机不播放。Scout仅准备N4 foreignownership定义/真实owner冲突入口与缺口报告，不实施/Flutter/ADB，不移高优先级tone-map。

- **HDR10正式释放Flutter/转独审实际验证**：作者确认全部handles终态（9161exit0，Root后pollmissing因已关闭），96PASS/Noissues/format3files0changed及三源一致已归档。正式释放Flutter给Reviewer，作者仅补artifactREPORT/toolstatus不再产品/工具运行。Reviewer48源/define/tool精确冻后必要helper/page接入/cleanup实际验证与build-only gate；禁止build/device，若产品问题Root接手。未approve/build/安装。

- **HDR10最终三源核对/候选刷新**：Root实际核对最终manifest page30099ddf/helper87e86d01/testf464936d全部一致，final-segment analysis日志No issues；作者56827确认exit0/96PASS，9161分析最后terminal交接仍待确认。48sources及全部当前tools/dependency hashes刷新draft，approvalfalse；未占Flutter/构建/设备，作者报告与终态待交接。

- **HDR10退出工具独立mock3PASS**：Reviewer实际runpy/mock-subprocess同步exit0，closed先于Launcher等待正确、debt拒绝、timeout partial stdout/stderr+receipt保留全通过；Root原日志回读归档。builder PASSdecision/reportSHA/toolsSHA/selfbinding及launcher nonemptyfreshRunId静态一致，仅工具预审不批准sourcebuild。当前三源manifest为segment修正前旧版，已要求作者刷新finalhash/report/terminal后才转Flutter独审。

- **HDR10最终跨sample修正96PASS日志**：Root实际回读tests-final-segment-r9最终96PASS，helper首sessionIdentity/sessionInstanceId/boundOutput完整JSON绑定已看；两替换反例green。48source draft刷新仍false，最终analysis/format/REPORT/toolterminal交接待作者，未夺Flutter。Reviewer独立hostmock验证退出collector lateLauncher/debt/timeoutraw，不ADB/Flutter。

- **HDR10中间analysisgreen/最后helper身份修正**：作者99195exit0/No issues，94PASS；source-manifest/frozen是最终跨sample修正前中间产物，不能终审。作者最后仅helper首sessionIdentity/sessionInstanceId+完整boundtuple/两反例，预计32+64回归；再有产品问题交Root。Rootverify-closed finally保留timeout raw，closed后独立等待Launcher同40s cleanup观察，不延长play120，syntax通过未执行。

- **HDR1094PASS/独审跨sample身份补门**：Root回读tests-final-r9最终94PASS。独审WIP发现跨sample只绑epoch/generation/entry可能合并不同Session/output；Lead要求最终最小firstsessionIdentity+完整boundtuple锁定/替换反例修正，仍未freezebuild。startuperror保留但实际cleanup成功debtfalse允许表达播放失败/清理成功，error仍非null不得播放通过，不将optionalproperty缺失升debt。Close实际等待顺序静态一致。

- **HDR10最终组合94目标实际运行**：作者75381实际live，30HDR10+64R9life/pageexit组合；28829exit1唯一testtransitive依赖info，test-only串行队列替代import、pubspec和生产Player.lock未改。独审先做当前WIP静态收口不占Flutter。Rootbuilder补exact独立report SHA/PASS_HDR10_SESSION_BUILD_ONLY与全tools hash/自身绑定门，syntax通过，toolinput排除自身manifest并更新，未approve或build。

- **HDR10分析仍需test依赖收口**：作者确认17439exit0/30PASS；Root实际回读analyze-repair单项test synchronized非直接依赖info，反馈不新增pubspec超范围，保留队列/drain反例语义。作者28829分析状态待其poll，Flutter仍作者独占，后续必要R9 life/pageexit+HDR10共94目标尚未完成。工具draft hash已包含strict run_deadline外部依赖，不作正式批准。

- **HDR10定向30PASS/固定源新完整字节核对**：Root回读finite-repair最终30PASS，无效Infinity/NaN反例已green；作者final回归/analysis/freeze仍待交接。8380实际LG完整exec-out source76438009B/SHA3068be37核对一致exit0/16.28s，receipt归档；仅资产身份，不作播放/HDR证明，未唤醒手机。源码48hash draft仍WIP须freeze刷新。

- **HDR10构建候选48源草案**：Root从R9保留源清单加HDR10 helper/test及classifier/planner/realizer共48当前WIP hashes，defineContract直接从builder AST提取（label除外）；hdr10-session-build-draft approvedfalse。必须作者freeze后刷新，旧R9approval不能批准此包。作者确认1975exit1 finite修正匹配没命中formatted真实入口，正在原反例重跑，日志不覆盖。未新build/安装。

- **HDR10首轮边界tests暴露非finite进度问题**：作者1975实际首轮日志Root回读27PASS/2FAIL（Infinity/NaN不得贡献10s progress），已反馈作者修复真实finite门而非放宽测试；未冻结/approved。工具R2静态P2关闭，Root补非空freshrunId、verify-closed只读finalschema与Launcher，syntax通过未执行；final工具manifest需绑定外部run_deadline依赖。作者Flutter独占。

- **HDR10外部anchor修正/实际反例**：Reviewer指出capture缺finite/start+120/serial/schema门；Root改为复用严格validate_anchor并验证installedmode/label/verified。实际有效120s及7反例（延deadline/NaN/错误serial/reusedrun/failedlaunch/900预算/expired）全通过，anchor-checks落盘。新增launcher syntax通过，实际前reportcleanup/包pm/wake/fresh120s run绑定唯一amstart，静态复核进行；display材料协议明确unbound环境不作同run证明。作者还未冻结或build。

- **HDR10安装/同run采证工具草案**：Root versioned install-verified固定hdr10-session并完整APK/lib回读；capture-journal绑定fresh anchor/run/label/mode/120s/hostboot、原deadline内最多12轮5s，保留每次rawstdout/stderr/errors，不宣称actualroute/panel/cleanup。两脚本syntax通过未执行，工具静态交Reviewer不占Flutter；作者仍产品唯一writer/Flutter，未freeze/newbuild/device。

- **HDR10 build-only工具草案**：Root新增hdr10-session-device-tools-v1/build-release.py syntax通过，固定普通HDRtransaction/PQ/HDR10journal、P5/N1/lifecycle/performance/loop显式false；必须独立approved exact defineContract/source hashes，JDK17/pinnedJAR/lib/prepostsource/package验证，不使用P5 builder。尚未approved/check-only/build/安装。作者初始analyze8lint已看，不接管写权，仍其首稿修正/测试。

- **R9 Home人工全项通过/严格关闭**：用户“都正常，连续播放”绑定run1791122235819593-550844699，完整画面/颜色/亮度/流畅性/连续播放接受。9639唯一Resume tap-1 end-certified；70676唯一Close tap-2 exit0/end-certified，真实closed/errornull/debtfalse、Session恢复verified/唯一Playerterminated completed/Launcher。timeout30000读回恢复并sleep，全部Roothandles terminal。human/cleanup/ledger归档；独立Surface最终ACK仍未证，HDR10工作未完。

- **R9 Home人工补验重测**：7844唯一coldlaunch exit0 run1791122235819593-550844699/original900s，timeout临时120000。实际Home Launcher证明，10724安全title589,560返回existingapp、same run/ManualResume enabled；9639唯一Resume观察进行，已询问完整画面/颜色/亮度/流畅性人工确认。未seek/reopen，当前run开放，最终cleanup/恢复30000未执行。

- **R9安全Recents人工接受/严格cleanup完成**：用户“画面颜色正常、流畅”绑定run1791121869088856-575810286，接受color/fluency，不扩为完整frame/亮度。17514唯一Close tap-2/end-certified exit0；实际final closedtrue/errornull/debtfalse、唯一Playertermination completed、Sessionrestoration verified、WM focusLauncher。timeout30000实际读回恢复并sleep；无liveRoot工具。human/close证据与ledger归档。Home人工transition仍缺、独立SurfaceACK仍缺。HDR10writer纳入Lead反馈继续首稿接入。

- **HDR10 helper初稿Lead检查**：实际读取新helper schema1/120s/256rows/4096text/6ownedbaseline，尚未tests/analyze冻结。反馈boundOutput非null不足需actual bound/完整tuple；progress有限位置与播放状态；gaps64上限显式overflow；write错误必须保留error/debt而非队列吞掉；要求作者必要反例，默认入口不改。page接入仍作者唯一写权。当前R9用户观察pending，未新build。

- **R9额外Surface连续性缺口**：58659两次同名SurfaceFlinger --latency exit0仅16666666刷新周期、无帧timestamp triples；duplicate Surface名字无法独立绑定，不能从此证明连续画面。原10s动作endpoint证书保留，人工问询仍pending，不作已验收结论，不重启当前run。

- **R9 Recents唯一恢复完成/后续journal静止**：87707 exit0/end-certified tap-1。78730额外三轮rawreport/SF采证exit0，但三次report相同elapsed50632/row3/time15.083，不当持续实时推进。实际ps PID24446存在、WM demo foreground；正常动作证书10s端点与额外静止journal分开。人工连续画面仍pending，当前run开放，不因report静止重启/seek。采证已归档。

- **R9安全Recents重测启动**：16433唯一coldlaunch exit0 run1791121869088856-575810286/original900s；初始playing/nonbuffering。49547安全title589,560单次tap exit0，实际Window focus为demo、same run、ManualResume enabled；87707唯一Resume正在观察，已请求人工连续画面。Scout正式report74a5dacf归档：历史libdovi crash比R9早16h不支持此次nativecrash；旧ps absent与缓存进程分开，不能从paused journal证明进程存活。当前新run仍开放，需最终cleanup/timeout恢复。

- **安全task-return工具草案**：Root新增精确SystemUI title locator，选择title中心并排除非祖先系统clickable control覆盖；实际home/recents XML fixtures通过（589,783及589,2270），注入clear-all覆盖反例拒绝。首版因背后task卡片bounds重叠过严失败已保留事实，修为只排除系统动作而非无id task容器。未实机执行新工具，需fresh overview/window与返回same run核验，不能当device通过。ledger已纠正旧Recents为误操作无效。

- **R9 Recents根因：Lead错误点击全部清除**：Scout指出card[64,2158,1376,2672]中心720,2415与系统全部清除[400,2394,1040,2578]重叠；Root实际XML/tap独立核对一致。不是已证demo崩溃，该次导航用例因外部误操作无效；trigger0tap保留，旧cleanup未证保留。已向用户承认自动化错误；需新增卡片安全可见区域/排除系统所有button覆盖的locator后重测，不重复该中心点击规则。

- **HDR10独立Release journal实施分派**：普通Session_openHdrSource与report日志入口Root已读；仅debugPrint不足LG空logcat取证。lg_manual_resume获page+新helper/tests唯一写权与Flutter，默认false仅固定PQ/normalHDRtransaction、拒绝P5/N1/lifecycle，实际report+同代output身份/有限采证+严格退出，不fakehint/loop/reopen/修改路由。先回报schema/退出方案，未新build/播放。Scout独立只读Recents进程异常，无共享写入。

- **R9重播人工通过/严格关闭**：用户“都正常”明确完整画面/颜色/亮度/流畅性，仅normal replay，不补造Home/Recents人工通过。80454唯一Close tap1/end-certified exit0；实际final closedtrue/errornull/debtfalse、唯一Playertermination completed、Session restorationChecks verified、Launcher；原timeout30000回读恢复并sleep。独立SurfaceACK仍缺。旧run进程消失cleanup未证照旧保留，Scout开始只读坐标/系统故障证据定位，不操作播放。

- **R9 Recents返回异常/用户要求重播**：overview卡片tap后实际foreground为Launcher，72275trigger严格locator拒绝、tapAttempts0，不能当ManualResume失败或通过。实际ps无目标进程，旧report frozen173639ms/closedfalse/cleanuppending；logcat空、API24 exit-info不可用，根因未知且严格cleanup未证。用户错过要求重播：保留全部旧证据后确认进程不存在，唯一新amstart产生run1791121423451177-1005497713/新900s anchor（不是延长旧预算）；实际native P5 playing/nonbuffering/time10s、errornull。人工观察已重新询问，暂保持播放，不继续导航。新run结束需严格cleanup/timeout30000恢复。

- **R9 Home实际返回/ManualResume一次成功**：ADB Home→Launcher取证→Recents精确media_kit_test卡片返回existingActivity，无amstart/reopen/seek；同run、paused ManualResume enabled。92237唯一tap1 exit0/end-certified tap-1，原900s anchor未重置；10s endpoint推进结构通过，人工连续画面/颜色/流畅性已询问待答。当前run仍开放，Recents独立用例与最终cleanup尚未执行。

- **R9构建安装/首次启动**：2022build exit0 APK61081cfe/lib7cc6f4ac；63778install exit0实际-2/base.apk完整APK/lib回读一致。LG唤醒ON/unlocked，原timeout30000保留、临时120000。55799唯一coldlaunch exit0 run1791121180929515-1032471876、原900s；initialreport nativeDolbyVision/实际OMX dolby decoder/同代Surface绑定，playing推进5s、bufferingfalse、无error/debt。正在开放播放并等待人工首次画面；Home/Recents/ManualResume尚未执行。run结束必须严格cleanup、恢复30000并sleep。

- **ManualResume正式独审通过/R9构建启动**：REVIEWaaaa69c3/reviewmanifest62129138 build-only PASS，Root核对43源及tool hashes一致；全部review handles terminal/Flutter释放。精确approval落manual-resume-build-approved，R9 session/lifecycle900s、N1false/performancefalse正式build handle2022运行；尚未APK完成/安装/播放。审核报告及冻结清单已归档，不把host67PASS当设备通过。

- **ManualResume独立运行日志通过**：Root回读independent-tests最终67PASS（3实际page提取集成+50life+14pageexit）及四源analyze No issues；Reviewer确认9079/20711 exit0，外部32mock observer tests通过。正式hash/report/build-only approval正在收口；未占Flutter、未构建或操作手机。构建draft43hash一致且旧N1/WIP元数据已修正，approval仍false；ledger同步R8真实fallback/cleanup及tone-map低优先级，保留所有历史。

- **ManualResume正式冻结/转独立审核**：作者final123PASS（50life+14pageexit+13diagnostic+26release+20N1），四源hash由Root实际核对一致；限定analyze/format通过、全部handles terminal/Flutter释放。正式REPORT及原日志已归档。独审接手必要运行验证与R9 build-only gate；尚未新APK构建、安装或手机测试，设备仍R8休眠。已向用户明确电脑自动测试不能替代实机验收。tone-map继续deferred，不构建性能包。

- **ManualResumefinal分析日志/HDR10报告归档**：Root回读64PASS与analyze-final No issues，四源manifest落盘、正式作者release待交接；43源draft刷新仍false。外部ManualResume精确/后缀/disabled locator实际检查通过；Reviewer实际targetcleanup静态P2已关闭。HDR10 REPORT4c6f2fab回读归档，默认Session facts识别后可baseLayerDirect Surface，但没有formal demo journal/实际bound与亮度证据，P5-only诊断不可替用。adb inventory仅LG在线，现代Vulkan回归仍缺设备，不将此提前判完成。

- **ManualResume64tests首验/HDR10输入核对**：Root回读tests.log新版64PASS（既有45+19），writer44526限定analyze live待freeze；Reviewer只读静态开始、不占Flutter。Rootffprobe固定PQ source：HEVC3840x1920 yuv420p10le BT2020nc/PQ/BT2020，30000/1001、30.097s、76438009B，不作真正HDR显示证明。HDR10route scout仍调查中；未新build/device。

- **ManualResume外部动作/设备协议准备**：versioned observer既有32tests PASS，run-one-action新草案syntax通过，严格原anchor/cursor/唯一下发/同request certificate，不把证书当画面通过。DEVICE-PROTOCOL固定Home与Recents独立出入、返回paused同run→唯一ManualResume、10s连续画面人工验收、最终原cleanup与timeout恢复；不以seek/reopen/强制pause补造用例。writer page/life已见ManualResume实现WIP，测试冻结待交接，Root无Flutter/build/device。

- **ManualResume构建草案/HDR10窄调查**：Root43源manual-resume-build-draft仍false，需writerfreeze刷新；versioned builder仅lifecycle/session，明确N1false/performancefalse，syntax通过。实际目标Home/Recents paused→唯一ManualResume→10s真实可见推进及严格cleanup。lg_sdr_performance_scout已转HDR10只读feasibility（不继续tone-map）：核对demo当前route与独立Java Surface路径缺口，不能移用探针验收。ManualResume writer仍Flutter独占，未build/install/device。

- **ManualResume设备流程草案**：Root新versioned install-lifecycle-verified/launch-lifecycle-verified syntax通过，绑定实际包身份、awake/unlocked、前N1/lifecyclecleanup与targetclosed、唯一amstart和原900s bootanchor；旧R7/N1工具不改。ManualResume locator/observer版本已准备，尚未执行；writer正在同Session/paused freshadmission+唯一play+10s推进封装，Flutter其独占。暂无新build/device。

- **ManualResume实施启动**：lg_manual_resume唯一writer page/lifecycle/必要tests，复用action admission+pageExit串行，paused非EOS/非buffering才启用，唯一play不seek/reopen，10s实际继续播放观察；保留disabled性能草案、不再性能工作，Flutter writer独占。Root仅新versioned外部locator/observer增加ManualResume（旧R7工具原样），syntax及既有observer tests通过；尚未产品测试/冻结/build/设备，HDR10在后续优先序。

- **tone-map后移/已启动审核终止收尾**：用户明确低优先级，Root将卡顿独立deferred置TASKS末尾，不新build性能包。独审26713已exit0/78PASS（5pageprefix+8sampler+20N1+13pageexit+32life），31158 limitedanalysisexit0，无livehandles/Flutter释放；REVIEW-DEFERRED e8986f43/manifest e5453a4e及原证据归档，无buildapproval。保留disabled-by-default源码草案及工具，不丢弃工作。优先manual Resume与HDR10等其他目标。

- **性能包43源清单/独立实际验证启动**：Root性能draft43源hash刷新、approvalfalse，未借R8review审批；context补verified性能身份及schema1/duration300前后门。summary脚本草案syntax通过，仅同身份相邻sample计数差、缺项不填0/人眼独立，未执行真实资料。Reviewer26713实际live，5pageprefix+8sampler+20N1+13pageexit+32life测试；page提取原主体/末尾native transport stub，不能作设备proof。Root停止产品/Flutter，无新build/device。

- **性能模块冻结/page分析通过→独审**：Root全文回读REPORT、8PASS/analysisgreen，module3e7f90aa/testdb813177冻结。Rootpage修补静态三点（perf单flag校验、accepted rawerrors原errorstack记录、外部context性能candidate+前后segment绑定）；新performance installidentity显式performanceEnabled。page16183 limitedanalyze No issues exit0，先前错误cwd/2lint及机械修正日志保留。Root全部handles terminal/停止产品写入，Flutter正式转android_fullscreen_mount_review必要实际集成与build-only gate，尚未新build/设备。

- **LG外部播放context采样准备**：Root新增sample-lg-playback-context.py syntax通过，固定原hostboot/anchor300s/run/label，只读GPU kgsl cur_freq/uptime/battery，2s采样最多120s，rawreceipts保留，未实际播放采样。现有通用GPU工具路径不适配LG；实际只读验证LG路径可读，idle214MHz/30.2C不作播放结论。sampler writer57006 analyze live，前7tests PASS，新tail-epoch/超长截断测试待8重跑。独审接Root page/工具静态，不占Flutter，最终待freeze。

- **性能Scout交接/新包工具草案**：REPORT2dc34f30回读归档，确认R8没有播放期性能计数，普通probe与N1互斥/API24 thermalstatus不可用；copy兼容决策不是根因。Writer采样API实际result已可接，Root page补拒绝reason/identity/rawerror留证，反馈epoch尾读/2048文本截断显式标记及avsync/fps/mistimed optional。新增独立perf builder草案仅N1/session+exactperformance define+helper/tests manifest，syntax通过，不改已冻结R8 builder。尚未page验证/新build/device，Flutter仍writer独占。

- **Root性能采样page草案已接**：page唯一writer Root，新MEDIA_KIT_ANDROID_PLAYBACK_PERFORMANCE_DIAGNOSTIC仅N1可用；真实open后bind epoch/gpu-next/copy、2s串行sample并记录performance行，退出cancel timer→await in-flight→drain→原cleanup。module writer仅新helper/tests，Flutter独占，API/result仍交接中；未format/analyze/build，当前源码WIP不能当已装R8行为。Scout报告待交接。

- **Release性能采样实施启动**：现有普通diagnostic采drop但P5需要nativeproof，N1回退没有性能采样；VMservice只Debug。Root分派lg_release_performance_sampler仅新helper/tests，既有锁只读path/epoch/vo/hwdec身份前后校验，time/drop/video params/vo-passes、unsupported保留error、有限行和无默认启用；不改N1/core/page。必要Flutter独占给该writer。Root负责后续opt-in接入与设备，当前无新播放/源码性能修复。Scout继续只读copy/指标事实。

- **N1 R8人工与清理完成**：用户确认“画面、颜色正常，卡顿”。真实回退呈现通过/流畅性失败，截图黑不代替手机反馈。25243唯一Back清理exit0，final closed/sessionClean/controllerRetired/playerTerminated true、debtfalse；SurfacereleaseACK仍unverified。原screen timeout30000已回读恢复并sleep，Root无live工具。N1配置/回退/cleanup闭环，SDR性能仍必须修复，不能关闭总目标。

- **N1 R8真实回退配置已证，运行仍开放**：16589单次coldlaunch exit0 run1791118877628450-n1/original300s；94017六轮采证exit0。实际native prepare1/configure0/open0、wholeprepare10061350us、同generation1/ordinal2 toneMapSdr gpu-next mediacodec-copy fallback prepare/configure/open各1；option恢复与typed route audit完整、无gaps/debt。截图视频区域黑，不能以configurationEvidenceComplete判断可见输出；已请求用户实际画面反馈，未close。Root临时timeout120000，须本run结束恢复30000；所有采证handles terminal，app仍运行，原anchor不延长。logcat空输出原样保留。

- **N1 R8构建安装身份通过**：正式独审PASS仅构建门，全部handles terminal/Flutter转Root。R8 build4484 exit0，APK df123fe3；install97669 exit0 pm path-1/全APK和lib回读一致。label lg-p5-negative-n1-r8-20261004；未amstart、无N1运行/视觉验收，Root无live工具。材料归档。

- **N1终验进程确认结束**：Reviewer实际poll51172 exit0/24PASS，53947限定analysis exit0；posthash与formal build-only report落盘中。Root准备close-n1-run.py语法通过/未执行：唯一Back后实际final cleanup观察，原run/label/package绑定，40s清理观察不作播放预算延长；SurfaceACK仍unknown。该新工具不纳入独审冻结清单，由Lead检查。

- **N1最终helper独审24项日志通过**：Root回读accepted-audit-and-n1.log最终+24 All tests passed（20N1+4独立实际audit/对照），对应accepted intake绑定，正式report/manifest仍待终交。只读核验PopScope Back触发同_exitNativeDvN1Page严格清理，可作为N1退出操作；没有新构建/设备运行。

- **N1 apply原值门补齐**：独审91838实际反例FAIL，Lead补同token captured原值/唯一apply/严格读回门；helper ef07786a，合并反例7PASS、20N1PASS、限定分析无问题，全handles terminal。主仓cwd0case失败及正确cwd复跑均保留；交独审必要终验，不重复未变core。未构建安装。

- **N1独审串行验证日志完成**：Root回读修正版actualaudit3PASS、core155PASS、lab89PASS、core/lab限定analyze No issues；全部原日志归档。正式final决策/source/tool manifests待Reviewer，尚不构建。初审中apply-original与captured-original绑定建议已回交Reviewer确认契约完整性，不能只以原两反例green作最终通过。

- **N1输入/安装准备**：Root39391实际完整ADB回读P5 289758635B，72.049s exit0，SHA dacfd045…匹配固定素材，材料归档。新增install-n1-verified.py草案syntax通过：安装后pm path/整APK pull及libSHA才写verified N1身份；未执行安装，交独审只读。修正版实际audit3PASS，独审core155日志PASS，最终lab/analyze/report待完成，Flutter仍独审独占。

### 2026-10-04 状态入口整理前的快照（历史，非当前状态）


- **N1 lab89PASS/工具cleanup门收紧**：Root回读test-final89PASS（20N1+69existing），correction2包含actualfallbackoutcome/route/ordinal和rollbackoldowner绑定负例；最终analysis仅专用test2bracesinfo，作者停止产品修改，Lead授权同轮机械testbraces+format/analyze/必要20重跑后freeze。Reviewer指出launch closed不足，Root已修首次R7必须actualterminationcompleted/errornull与最后Sessionrestoreverified；negative必须sessionClean/controllerRetired/playerTerminated/closed/debtfalse，不丢启动失败原debt。工具syntax通过/未设备，正式N1gate仍false。

- **N1外部冷启动草案已准备**：Root新增launch-n1-run.py syntax通过、尚未执行/未freeze；要求installedidentity verified+negative-n1mode/packagePath，AwakeON/unlocked，前negativeclosed/playerterminated/debtfalse或首次R7closed，启动前hostboot/300soriginalanchor，only1amstart发现freshsamecandidate，不延长/重试。命令超时stdout/stderr/receipt finally保留。交独审只读工具边界，无Flutter，Root安装后需identity带diagnosticMode。labcorrection2源码已见实际route/outcome/rollbackowner更严，尚无finaltests/freeze，N1buildfalse。

- **N1 lab首修86PASS / 外部采证草案**：Root回读test-correction1 actual86PASS/returncode0（17negative+相关diag/life/page），这是syntax首修版本，不含随后audit严格binding反馈，不能作final。下一集中correction仍进行/Flutter lab。Root新增capture-n1-sequence只读工具：hostboot/original300s anchor/run/label/schema/mode绑定，before/afterreport+screen/SF/window逐命令receipt，超时raw/stdout/stderr finally保留，不推断验收；syntax通过/归档、未设备执行。N1 approvalfalse/未新build。

- **N1 core正式报告归档 / lab修正反馈**：Root全文回读REPORT31029ed6/manifest91c029cf，五SHA再次核对并归档；保留155frozenPASS/analysisgreen、0cases配置/编译失败和fixture修正记录，不将词计数/默认backend早期失败fixture作真实slot proof。lab首format/test parser0cases失败，集中syntaxcorrection1后format成功；Reviewer只读发现audit entered≠returned/实际backendroute未typed绑定/reset旧owner未绑定，Root交lab下一集中correction+针对负例，不提前build。Flutter lab独占，Reviewer静态，N1draftfalse。

- **N1 core冻结/Flutter转lab**：作者明确四core+newtest冻结、63702final155PASS/96775analysisexit0/format0changed，all11handles terminal停止；Root回读source-manifest五SHA核对，await表达式相等仅text证据不作调度证明。lab正式获Flutter进行necessary tests/analysis/freeze，独审core只读不Flutter。N1 draftfalse已绑定core/newlabWIP/negativeexactdefine，未构建/安装，不能沿用R7review作N1approval。Root设备无livehandle。

- **N1实现验证推进**：core writer报告组合155PASS/最终限定analysisgreen，Root回读27diagnostic日志PASS；正式freeze待交接，Flutter仍core独占。Root回读lab bounded runner草案，反馈RouteApplied verified与typeddegraded目标一致、prepare整体duration不冒称精确boundwait、cleanup归属避免污染counts，纳入lab首验证。Root新增N1 buildrunner独立草案syntax通过，negative-n1 exactdefine与必需sources门，仅工具未执行/未approved。所有N1依然非设备验收，R7 manualresume入口后续。

- **R7手动恢复入口缺口**：新run1791116478398499-181384416 coldlaunch/3rows后Home返回paused，69692实际返回同Activity（未重启）。视频controls源码仅contextcapture+SizedBox，无Play accessible；一次屏内触摸未播放，第一次UI dump nullroot（screenAsleep实际核实）保留，唤醒后再dump无Play。未以Seek/reopen替代manualresume；此项仍缺入口/持续播放证据。Root临时timeout120000，21034唯一close清理（观察结果见runner），随后恢复30000并sleep；材料归档。labwriter先冻结N1，不混入resume扩范围，之后窄补入口。

- **R7 Home/Recents导航与暂停事实**：91567完整exit0，同run foreground分别Launcher/应用/Recents/应用，报告row7后不增加、position约34s/playingfalse；返回截图正常完整小窗。Video默认background pause=true/foreground resume=false源码匹配，不判继续播放通过，需手动resume补证。首healthyclose76368 locator0tap失败保留；唤醒解锁后70630正式唯一Close执行（结果见healthy-final-report/observer），材料归档。保持原anchor不重启。N1两writer继续，未新build。

- **R7健康run唤醒后恢复/往返实机进行**：48198 readiness40s失败（report停elapsed545/rows0），核查AsleepOFF/keyguardtrue，保留该失败不重启。同run1791116207659969-579525501唤醒解锁，88651capture3完成；elapsed97306 rows3/debtfalse/errornull，实际采样恢复。Root91567 Home3s→sameActivity返回7s→Recents3s→Back返回7s采证live，首before rows7/errornone/debtfalse；完整往返与healthyclose尚未判定。原anchor不延长，R7与WIP来源分开。

- **R7 failed-startup Back通过/健康回归启动**：24342恢复全素材SHA完成exit0，22446唯一系统Back后verdict通过；run1791116054322628-636583140 finalclosed/debttrue、原startup error不变、actual Session restoration verified/player termination completed/Launcher，无伪endcert。Close/Back两case原资料/Lead verdict归档，ledger同步该恢复验收，SurfaceACK仍未证。Root启动R7cold-launch-healthy待正常/HomeRecents/healthyclose；core+lab两writer继续，不把WIP源码当installed包。

- **R7 Back startup已复现/台账同步**：Root24342 live，run1791116054322628-636583140，真实startup8s timeout/debttrue，素材已restore命令，完整SHA回读待完成，尚未Back。lg-current-test-ledger已分开R6 fullscreen人眼color/fluency、结构两轮、截图black不作实际黑屏，以及R6恢复误报失败/R7Close保留原error/debt恢复通过；历史R5视觉失败未丢。核心/lab两个writer继续，Root无Flutter/build，R7实际安装包与WIP源码分离。

- **R7 failed-startup Close 通过修正验收**：Root92458恢复全P5SHA完成exit0，55993唯一Close1tapexit0；run1791115834154231-635312793 closedtrue/debttrue，final error等于原startup8s timeout；实际Session restoration verified/player termination completed、Launcher focus，未生成close end-certified。Lead verdict与原report/window/source/trigger完整归档，独立SurfaceACK仍unknown。R7 Back独立case已启动（toolhandle），待全SHA/失败/恢复/唯一Back。核心/lab两个writer继续，不新build，未提交。

- **R7失败Close startup已复现**：Root92458仍live，run1791115834154231-635312793，实际8s timeout/原error/debttrue/closedfalse，finally恢复命令已执行、完整恢复SHA回读中，尚未Close。R7 healthyaction runner准备未执行。N1两writer按files隔离：n1_core_observation四core+tests/Flutter；n1_lab_fixture page/newnegativehelper/tests仅编辑，直接协调已给API，默认页保持/真实私有slot+10s/一次open/typedfallback/实际双optionrestore/严格cleanup，尚未冻结/审核/build/device。

- **R7已构建安装身份通过**：Root65514exit0 APK9279aefc/lib7cc6f4ac，42557install/pull/完整APK+packagedlib SHA一致。R7失败Close脚本开始live（见toolhandle），待全P5SHA→临时rename→真实失败→finally恢复→Close。N1独立架构REVIEW8cef0798/source-manifest8eb236d1 Root全文回读归档，四core观察方案批准实施；n1_core_observation独占4core+必要tests/Flutter，Root仅R7 ADB，不新build。待观察接口freeze/独审后再lab触发与新包，不能迁移为N1device通过。

- **R7已批准构建并运行**：独立REVIEWaa66e5de/manifestdf3a4605正式build-only PASS，Root全文回读、hash与37sources核对归档；所有独审handles terminal/释放Flutter，Root接构建65514 live。R7 approvaltrue、session/lifecycle900、label lg-p5-session-lifecycle-r7-20261004，原lib7cc6f4ac/JAR23036e0b保持，APK尚待产物，不称installed/runtime通过。R7失败Close/Back与healthyclose待实机，SurfaceACK未知；未提交推送。

- **Recovery独立48PASS/分析通过**：Root回读独立production-and-regressions48PASS、old反例实际exit1和限定analyze No issues；正式REVIEW/posthash/运行权释放待Reviewer，不提前build。R7draft补齐session/lifecycle/900定义（之前只sources缺模式，已纠正），approvedfalse。N1独立架构已确认方向成立但operation.timeout不等于底层Future结束、rollback/dispose需旧attempt身份，计划细化中无source改动。

- **Recovery冻结/独审启动**：Root全文回读REPORT5697f1ab/manifest5f1f6f97，6source核对归档；作者全部handles终止/Flutter释放，android_fullscreen_mount_review已正式获独立3生产边界+旧反例+45回归/analyze权。R7draft刷新finalhelper2d2cf61c/lifeTestcacd7e9e/pageTest1b5e8d58仍false；R7失败设备脚本已准备并加120s读回watchdog，仅syntax未执行。N1推荐保持production slot的4core受限sync观察方案已归档51c345e8，交n1_observation_design_review独立只读架构复核；尚未产品编辑/设备，不能把设计当通过。

- **Recovery final静态门已核对**：Root回读作者3items analyze No issues/format0changed及final45PASS；正式REPORT/source-manifest尚未生成，不视为freeze，独审不得Flutter。N1替代方向已确认现onPhase只有await后successmark且不透出rawerror；真实私有slot路径完整采证至少需受限同步边界观察+既有owner已读值转发，不新增async读/锁/await，不按successmark伪算entry。只读设计补充中，未core改动。

- **Recovery最后45PASS / N1证据方向**：Root回读tests-final.log45PASS及保留original/current/throw三者helper；正式freeze/analyze尚待作者。独审已验证旧函数baseline字节精确提取与R6实际误报。N1初版只读设计归档：普通页门能真实prepare10s timeout，但现API缺rawerror/调用计数；另slot+forTesting方案改变输出接线，Root未采纳实施，要求只读补真实coordinator观察入口最小方案，保持私有slot/HdrVideo路径。R7draftfalse，未build/设备。

- **Recovery 修正版验证/独审准备**：作者旧helper准确反例exit1，当前完整45tests日志PASS但作者最后analyze/format/freeze未完成；新增测试覆盖startup原error + terminate内部markDebt后真实throw，以及ACK失败独立Close action failed分类。Root回读helper窄范围，已派android_fullscreen_mount_review只读V1、Flutter等待作者释放。R7 draft approvedForBuild=false，37源snapshot/相对R6仅3处差异记录，不构建未审核candidate。

- **R6 failed-startup Back 结果**：Root74931恢复SHA完成exit0；独立run1791115028744728-326961869，唯一系统KEYCODE_BACK，Root95570exit0，closedtrue/debttrue/实际Launcher。报告同Close误报 Owned termination failed...Lifecycle run is closed，材料已完整归档。不是R6失败退出全面PASS；待窄helper修正独审/R7两case复验。Root无live设备handle，结束熄屏；writer Flutter/只读N1设计仍进行。

- **Back 独立失败case执行中**：Root74931 live，R6 fresh run1791115028744728-326961869 已实际startup8s timeout/debttrue/closedfalse；素材finally恢复命令已执行，完整恢复SHA仍回读，未触发Back。上一Close报告误报已交writer helper+专用tests窄修；允许专用page test旧误报断言更新，不改page产品，Flutter writer独占。native_dv_backend只读定位N1真实Surface抑制/timeout采证入口，无编辑/Flutter/ADB权。

- **R6 failed-startup Close 实机结果**：素材恢复全字节SHA与原始一致，Root90497exit0。run1791114780283184-1015157631 唯一close-trigger37504exit0/1tap；最终closed=true/debt=true，session-disposal-proof恢复全匹配、player-termination completed、window focus实际Launcher。但error新增 Owned termination failed before final report: Lifecycle run is closed，原startup error被该拒绝包装取代。不判清理全通过；helper在terminal/debt仍runAction导致预期拒绝误标termination failure，已交原writer lg_failed_exit_fix窄修及回归，保持debt/原失败/flush gate，不伪证书。Root已归档完整failure/restored/afterClose/trigger材料；Back独立case尚未执行。

- **失败启动实机已复现**：R6 failed-exit-close run1791114780283184-1015157631，原P5全字节SHA匹配后临时rename；实际startup timeout8s、debt=true/closed=false。finally已执行恢复命令，完整恢复hash回读仍由Root session90497运行；未点击Close、不能判退出通过。工具r6-failed-exit-device.py/原报告在host R6 failed-exit-close目录，下一步收取同handle，再唯一Close及最终清理/foreground证据。

- **R6 实机更新**：R6 APK4076bcf9 installed byte verified; run1791114202354108-117282616 default FullscreenRoundTrip tap1/tap2 end-certified; close-and-exit tap3 end-certified, closed=true/debt=false/error=null, player termination completed, idle restoration verified. User confirmed fullscreen colors normal and smooth; full-frame/no-overlay/brightness not explicitly answered. Screenshot black is preserved as capture evidence, not physical-screen black conclusion. Independent Surface release ACK unverified. Initial close runner invalid action name rejected before tap; corrected close-and-exit one tap. 失败启动Close/Back、HDR10/P8.4/SDR性能、现代设备回归仍待测；未提交推送。

- **R6 build gate approved**：独立全屏REVIEWb18a9c8f/manifest725317f3 PASS，Root全文回读核对与归档。退出独审55475944仍有效；R6原30源加独审protected相对path绑定共37源hash核对，新approvaltrue仅buildgate。新增ledger为当前独审绑定，不称R5此前绑定。全部Reviewerhandles终止，Root接Flutter构建；实际图层/连续帧/失败CloseBack仍未验收。

- **全屏独立24用例PASS**：Root回读独立permanent8/route14日志，integration2已核对，共三层各scope通过；Reviewer旧rollback反例62794exit1 original/reportermask独立复现。唯一live7249finalanalyze，后hash/正式report未freeze，不扩大复跑。R6draft仍false/未build，实际LG连续图层与失败退出仍缺。

- **独立VideoState两整合PASS**：Reviewer隔离copy首次缺package_graph未执行，保留log；补原配置未clean/pubget工作区，v2 session76429exit0，实际VideoState Android输出分支与pendingTexturelayout取消两项通过，原生transport stub不证明JNI/SF。Reviewer继续顺序8/14/analysis，Root无Flutter。R6draft30源hash复核保持/false，LG read-only在线且两素材size正确/Asleep OFF，不升字节hash或显示验收。

- **全屏已freeze独审运行权交接**：Root全文回读REPORTadbd67c9/source manifestd73e126b并核对6sources后归档，fullscreen74f7c977。作者所有写入/handles停止，Flutter转android_fullscreen_mount_review实际VideoState/pendingTexture整合与必要独立复验。8永久/14route/30定向/7release各通过，原entrycontract0加载失败/分析1baselineinfo不冒PASS；nonAndroid正常1test在最后Androidguard修改前，shared异常logger改善明确不称byteexact。R6draft30hash已核对approvedfalse，等待最终独审，未build/ADB。

- **全屏rollback反例闭合**：旧副本76359 actualexit1期望original enter/实际reporter failure，确证直接reporter mask原error；修正版android-route-v4 14PASS（13232exit0），Root日志回读。Navigator override在mutation前throw用于隔离验证，非真实framework坏锁复原证明；remove失败保留route/lease、明确retry后once nativeexit与释放通过。77522最后analysislive，formatv2exit0，作者即将freeze，Reviewer实际VideoState整合待授权。未新build/ADB。

- **R6连续图层采证准备**：Root新增read-only capture-session-sequence.py（SHA 5764759d），每轮before/after report绑定同run/label、同host anchor deadline；截图+SF+window逐命令UTC/monotonic起止/returncode/raw stderr保留，不执行tap/不推断验收，py_compile通过、尚未设备运行。core回滚双throw窄修仍实施，独审VideoState实际输出/pendinglayout harness准备完成；旧entrycontract未执行加载失败保留、owner未变前提待hash证明。

- **全屏剩余审核边界**：release-regression-v1 7PASS，Root回读；final analyze exit1仅baseline同constVideo Key?key use_super_parameters info，不称green/不扩大无关lint。worker38743实际entrycontract回归后补受影响真实nonAndroidcase；Reviewer指出rollback removeRoute catch直接reportError在observer/reporter双throw时可能mask原enter异常，Root交writer核对窄guard+反例，尚未声称复现。独审计划补真实VideoState AndroidPlatformView分支与pending Texturelayout取消覆盖（现helper/harness未覆盖全分支），只读隔离copy/platform-only替换/mock transport，不迁移为Java/SF通过。freeze未完成，R6仍false。

- **全屏候选主机13+30PASS**：Root回读android-route-v2.log13PASS（原生产源码仅platform判定替换），regression-v1.log30PASS（owner ledger/HdrBody/fullscreen scope/Texture layout）。8永久tests保留；worker尚需Surface release定向回归/最终analysisformatfreeze，无新产品编辑。android_fullscreen_mount_review已接V1只读，禁止Flutter直至worker终止释放，重点lease/notifier/nativeexitonce/rollback/真实defaulttransport；真实LG图层/连续帧/返回仍待下一APK，R6未approved。

- **全屏主机验证进展**：永久production Body/Host/HdrBody/lease/notifier/真实非Android/default tests-v2 8PASS，Root日志回读。仅平台判定替换的实际Android route harness v1 10PASS/1fixture fail，null-gap finder默认skipOffstage排除保留窗口导致Expected2/Actual1；worker修为明确include offstage，产品未因此改动，v2 handle13727实际运行。新增push attach throw/reporter throw边界；route callback once/lateenter settle实现已落。尚未freeze/独审/新build，JNI释放与可见全屏仍待LG证据。

- **退出v2独审PASS（build gate only）**：Root全文回读/核对REVIEW55475944/manifest9dba41a6并归档，旧v1两实际产品失败+两PASS，v2同4生产反例+原41共45PASS、4fileanalyzegreen/format0、6sources后hash保持。Reviewer全部handles terminal/停止写入，Flutter现转android_fullscreen_mount_fix。实际失败Close/Back恢复、独立Surface释放仍缺，不迁移主机结果到设备；R6仍未批准构建，等待全屏候选冻结独审。

- **退出v2已freeze转独立复验**：REPORTa2ba00f5/manifesta1974810，Root核对4owned源/审核材料hash并归档；page1eee9669/newtest4fbc97dc/helperc7a5c951/helpertest93487290，41PASS/analyzegreen/format0。作者所有handle终止，Flutter转lg_failed_exit_review v2独审。core fullscreen仍仅编辑，新增removeRoute/onEnter失败后native状态恢复once callback纳入必要rollback，非Android/customscope保持。无新build/ADB/提交。

- **退出v2修正回归41PASS**：Root回读tests-corrected.log；故障清理markDebt先schedule写、close置closed后enqueue最终写，两延迟snapshot都可观察closed，fixture按healthy1/termination-error2精确核对，仍要求exit0/termination1/错误债务保留且重复close不新写。之前错误cwd导致未应用fixture的两失败轮原日志保留。作者当前最后analyze/format/hash冻结中，尚无v2独立PASS。core全屏产品与测试/harness准备就绪、无liveprocess，等待退出独审后运行权。

- **退出P1旧实现实际反例已证**：writer90567 exit1，Root回读before-fix-counterexample.log Expected exitCalls0/Actual1，原helper确实finalwrite失败后pop；不是静态推测。v2首回归40pass/1fail（terminationFails=true期待final write count1实际2），原日志保留，writer定位必要fixture，不得放宽不exit/once termination/错误保留断言。运行权交接交叉core13308曾已启动，后明确exit1 fixture import compilefail未跑断言；当前已终止，exitworker独占继续。两个candidate仍未冻结通过/未构建。

- **退出V1正式静态REQUEST CHANGES**：Root全文回读REVIEW96502eca/manifest5c43b778并归档，1P1 finalwrite失败仍pop；反例绑定冻结page与byte-exact helper，runtimeExecuted=false，不能宣称独立复现已经执行。其余增量未见静态blocking。v2 finalReportCompleted gate已落WIP，Flutter仍归原writer，待作者测试冻结后独立生产反例/复验。

- **串行测试权更新**：core fullscreen worker初次analyze仅既有super_parameter info、无新错误，5files+helper初步实现/format，tests编辑中（错误cwd写入ENOENT未启动test，保留日志），明确无live handle；Flutter暂转lg_failed_exit_fix v2必要测试。v2最小finalReportCompleted守exit：仅await run.close成功才pop，失败留页/错误/termination幂等，不更改closed schema或deadline/债务，原close失败Future不提供伪成功重试。R6新增source/test gate requirements已创建approved=false，待两个候选独审，不构建WIP。

- **退出独审新增阻断**：Reviewer静态确认既有close helper捕获run.close finalwrite失败后仍调用exit，closeOnce先closed=true再awaitfinalwrite；违反本轮最终报告完成才退出目标，Root纳入blocking而非范围外豁免。原writer correction1接回page+lifecyclehelper/tests/newpage test，v1材料保持，新v2目录，暂仅编辑无Flutter；需真实finalwrite失败不pop、错误保留且不伪造closed成功，保持termination幂等及deadline/债务。Reviewer先正式v1报告，core fullscreen writer仍占Flutter。未构建新包。

- **失败退出候选冻结**：lg_failed_exit_fix pagefbbd9104/newtesta6318190、REPORT6fa09e0a/manifest69ba158a，Root四hash核对并归档；最终37PASS（12生产page控制+25原lifecycle），限定analyze无问题/format0changed。作者终止所有写入与handles，Flutter转android_fullscreen_mount_fix；lg_failed_exit_review已接独立V1只读，暂不得Flutter。实际故障Close/Back采证尚缺，新包approved=false/未构建。

- **退出修复回归进展**：Root回读lg-failed-exit-v1/test-combined.log末尾37tests PASS（新page exit生产控制用例+原lifecycle），analyze.log仍2 curly info，尚未冻结/未独审/未build。错误reporter守卫、no-run实际dispose留页、未跟踪busy安全拒绝且仅pretermination可重试已落WIP；worker继续最后修正。全屏core挂载租约worker已保存baseline、实施中，无Flutter权。

- **全屏实施已接入**：Specialist冻结DESIGN e0b087ff，Root全文回读接受；android_fullscreen_mount_fix独占core Video/HdrVideoBody/default fullscreen/必要FullscreenInheritedWidget/new internal lease+tests，编辑先行，无Flutter权。方案在Android窗口整个outputbody/layout report之前暂停挂载，稳定HdrVideoBody租约跨controller null，fullscreen独立scope，route.completed释放不持lock，快照callback/参数并保活共享notifier，保留严格旧Surface destroy/stop/release协议。lg_failed_exit_fix仍独占lab page/new tests/Flutter，Root已反馈await失败记录不得跳过termination。两分支无新build/ADB。

- **下一增量已分派**：只读Specialist android_surface_visibility_design已核实API24 AOSP SurfaceView无alpha覆盖，visibility更改会destroy Surface，不接受无损INVISIBLE假设，正在设计默认fullscreen精确VideoState原生挂载暂停/返回重建方案。Escalated writer lg_failed_exit_fix独占lab page与新增专用测试/Flutter，修复失败debt/terminal后恢复Close与系统Back await严格termination/final-report，busy等待与重入保护，不清除原失败债务、不改证书/普通动作/默认fullscreen。Root无Flutter/ADB，未新构建。

- **R5 实机结果（最新）**：R5 APK7f5754d7已构建安装且installed APK/lib回读一致；run1791111316759322-554035962：P5SDRP5 tap1、默认FullscreenRoundTrip tap2、后close tap3均end-certified。但带host时间边界的fullscreen截图仍明确旧小窗覆盖，视觉全屏失败，不能由动作证书替代。首次SDR locator屏外0tap保留，滚动后唯一tap。失败状态Back/close、HDR10/P8.4/性能/现代设备仍缺。

- **R5 build gate approved**：独立组合V1 PASS（REVIEW7b0e7b0f/manifest95c47d3b），24诊断、4实际生产全屏action提取测试、1官方marker测试及限定analyze通过。Root核对23源码与审核hash，新建R5 approval=true，仅批准构建；实际全屏旧小窗叠加、切源与失败退出验收仍开放。

- **R5 双候选已冻结交独审**：Fullscreen context v1 page861ace27/REPORT49a80b5a/manifest6c0d4232，host提取capture helper官方marker1test及analyze/format通过；两个context槽保留所有原scope/5s/surface/source/deadline，旧小窗叠加未宣称修复。SDR active-contract v1 48诊断+生命周期通过；Root发现新typedRoute错误证据自由字段未bounded，worker correction1 v2仅边界修正：diag9601f9aa/tested17890c/REPORTa3d2b943，24diagnostic通过、128字符/最多8依赖及实际拒绝path<8192负例通过，继承未变lifecycle测试证据。R4三源baseline与diff/失败日志均保留。新独立Reviewer lg_fullscreen_sdr_review running，Flutter已交Reviewer，正独立诊断与加强实际fullscreen action验证；Root无live工具/ADB。R5 approved=false draft23-source全核对，除3owned外20与R4一致，尚未构建安装。验收ledger已新增 lg-current-test-ledger.json，6设备结构动作与2失败、人眼R3正常/healthy退出/Surface独立释放unknown分开记录。

- **R4 实机新证据（最高优先）**：组合独立V1 PASS REVIEWa9a0dbf2/manifest8f6e086b 后23source核对构建安装 R4 APK6f29514f，installedAPK/lib字节hash匹配。单scroll实机生效，8按钮底部可达。run1791108968766600-483579034 FullscreenRoundTrip tap1失败：scope判定error，但截图已横屏fullscreen且叠旧小窗；报告新viewId1/surface与新generation表明确实构建fullscreen，不能说UI完全未enter。run1791109072036176-771121541 RecreateSession tap1 end-certified，rows分session1/session2、真实qcomDV/timed，后close tap2 end-certified/closed/debtfalse。run1791109199842373-153993866 P5SDRP5 tap1增强证据明确：实际video/avc OMX.qcom.video.decoder.avc/native=false，DV pair空/boolean匹配idle，typed/actual copy/gpu-next；仅hwdec/current vs idle no/空两项失败，随后admission60s timeout。已提取sdr-rejection-evidence.json并保留完整原report/observer；失败后force-stop/sleep，不能算strictcleanup成功。R4材料已归档。
- **当前两个 writer/共享运行权**：lg_hwdec_restore_fix仅page修复windowed/fullscreen两个context槽（保留官方scope、surface/reopen/deadline gates，叠画面问题待后续实际观察），当前占Flutter；lg_sdr_active_contract仅diagnostic+test修复activeSDR按同generation完整typed Applied检查hwdec/vo/current、DV pair仍比最初idle，最终cleanup完整idle保持，先编辑不得Flutter。独立设计已给精确checks/正负cases；Root无Flutter，R4完整P5/SDR设备字节hash刷新已完成且一致，无Root live handle。
- **另确认待处理退出入口缺口**：R4冻结page Session诊断build直接return Scaffold，无其他auto分支PopScope；debt禁close按钮，系统Back可先Activity退出、dispose采证异步导致pending。后续要接await的严格Session+Player退出路径并验证失败状态可安全终止，不得用returnedLauncher补写cleanup pass。当前page writer不扩此项。

- **目标与授权**：LG-H870DS API24 能力检测及 hdr_lab 移植实施仍 in_progress；安装、设备实验已授权，未提交/推送。保留其他 Darwin/共享 renderer 修改。
- **设备与实际显示**：LGH870DS42e27764，Android7/API24、Adreno530/arm64；声明 HDR10/DV、无 HLG。R3 `lg-p5-session-lifecycle-r3-20261004` 用户答“都正常”，确认完整画面、颜色、亮度、流畅性。独立原生 P5/HDR10 的正常观感与 R3 demo 验收分别记录；旧 SDR 映射“颜色正常但卡顿”仍未解决。设备最后已熄屏、timeout30000，无 Root live ADB/test/build。
- **R3 版本身份**：APK `09a4728b5ab119a4bc7f7fddfc4cd431d550ff36f223dfcf5529819c04728412`，lib `7cc6f4ac`/JAR `23036e0b`，23 source build前后匹配；installed APK/lib和P5/SDR完整设备字节hash匹配。材料 `archives/experiments/artifacts/lg-hdr-20261004/native-dv-session-lifecycle-release-r3`。原始构建APK留 `../media-kit-build/lg-api24/native-dv-session-lifecycle-release-r3`。
- **已验证动作**：run `1791107639256966-185208592` 的 Pause10Resume、Seek90Then30、Reopen40Then10 完整 end-certified 在原900s host deadline内收到；run `1791108168949954-774541706` RestoreSurface 同样采证。动作证书不替代每个转场的人眼验收。
- **健康退出修复通过**：run `1791108040023988-1017702864` close-and-exit end-certified；closed/debtfalse、source/epoch/codec/options baseline verifiedtrue，hwdec恢复no、player-termination完成，实际Launcher。RestoreSurface补测run随后close同样closed/debtfalse。独立Surface release ACK仍不可观测，保留unverified。R2 hwdec恢复失败由controller先写/owner后capture导致，修复在controller创建前登记原值，已独立审核+实际健康close证实。
- **P5SDRP5 失败未解决**：R3 tap4 SDR routeApplied报告sdrDirect/h264/mediacodec-copy；segment row0在AVC/idle-options复合predicate被拒，之后60s等待row admission超时。失败实际属性未持久化、logcat空，不能判唯一失败项/真实AVC wrapper或锁阻塞/EOS根因。idle hwdec=no/current空与active copy route存在预期冲突，但未改predicate。debt禁全部动作，close零tap locator拒绝；Back返Launcher仍cleanup pending，不算正常退出。失败现场已归档，后健康新run退出独立记录。
- **当前候选已冻结**：仅SDR拒绝采证增强 `lg-sdr-rejection-evidence-v1`：diag `7801b2c742b6879ffe316a74b1c6947ef2f83b62b992eaa7533ffb021b67dd0e`、test `b68e1b531f811fb1be975289186ae6c779872cd83262d1bcf515a25cac68bf02`；19 tests/owned分析格式通过，REPORT882088db/manifest1f2281f1。接受条件不变，已有segment.error新增有界actual/expected/命名failed-mask及identity证据。Root 单scroll页面 `lg-session-layout-v2` SHA `28de4577b31891cecda30adb6d13c8b82b3d17432b0adcee889cd05816db9575`，仅删生命周期controls内层scroll/maxHeight；format/analyze/diffcheck通过并停止写入。
- **当前审核/共享运行权**：`default_ps_api_review` running 新组合V1 `lg-sdr-evidence-single-scroll-review-v1`，重点predicate语义不变、有界拒绝证据及实际8按钮横竖屏滚动/tap；首轮诊断19PASS但审核controls替身Map类型错误导致合并exit1，原log保留、按生产接口修正替身复跑。Reviewer占Flutter，Root及worker均已释放。不得重复旧ownership broad103或并行Flutter。
- **R4 状态**：`../media-kit-build/lg-api24/native-dv-session-lifecycle-r4-build-draft.json` approved=false；23-source匹配，除3owned外20项与R3一致。独立审核通过后方可绑定报告并批准构建/安装；当前未构建R4。下轮采实际失败mask，再决定SDR active route与idle teardown的正确验收契约，不能凭推測放宽。
- **剩余完整范围**：FullScreenRoundTrip/RecreateSession 未执行，R3内外scroll导致底部按钮不可达，候选修复须真实验证；Home/Recents独立往返、完整生命周期/失败后退出清理、真实故障回退仍缺。随后固定HDR10 boolean→timed→boolean对照、SDR映射/P8.4性能、现代Vulkan回归；不降低默认nativeDV成熟度门槛，不标任务完成。
- **工具与证据边界**：cold-launch前hostmonotonic固定900s，tap不重新预算；UI唯一enabled Semantics单tap；observer完整root certificate原deadline内抵达。旧end/step证书不算root成功；collector绑定installedAPK/lib/source。外部工具/旧审查/准备方案精确SHA保存在历史及artifacts。静态分析/测试/安装/decoder路径均不代替实际画面验收。


### 同步整理前的LG任务台账（历史）

- [ ] LG-H870DS API24 HDR能力检测与 hdr_lab 移植
  - active-work: R7 APK9279aefc安装身份通过；failed-startup Close实机原错误/debt保留、restoration/termination/Launcher通过，独立Back复测进行。N1观察4core与lab fixture分文件实施、Flutter串行；Surface最终释放ACK仍缺。
  - newest: R6 APK4076bcf9 installed回读一致；默认全屏两轮/healthy关闭结构通过，用户确认全屏颜色正常、流畅。失败启动Close与Back各独立run已实际termination/idle restoration/Launcher，但均新增预期拒绝误标termination failure并覆盖startup错误，故不判全面PASS；窄helper/tests修正回归进行，待独审与新包实机复验。未提交推送。
  - next-evidence: R3 RestoreSurface另健康run采证通过；全屏/重建Session控制入口被嵌套滚动阻挡，Root单一scroll候选待检查。SDR拒绝字段增强19tests通过并冻结，原predicate保持；单scroll页面与采证增强组合独立审核running，R4 draft approved=false。
  - current: R3 已安装/回读APK09a4728b；人工完整画面/颜色/亮度/流畅性“都正常”。暂停/跳转/重开3动作证书通过；P5SDRP5因SDR采样谓词拒绝后超时失败，正在补实际失败字段证据。另健康run严格close通过、hwdec恢复no/全部baseline verified/player终止/Launcher，Surface独立release ACK仍缺。设备已熄屏，未提交推送。
  - status: in_progress
  - context: archives/conversations/lg-h870ds-hdr-demo-20261004.md
  - acceptance: runtime能力；demo SDR/HDR10/P8.4/P5/nativeDV明确路由；Release画质/性能、暂停/seek/全屏/重入/Surface恢复；原生HDR人工验收独立。
  - latest: API24兼容、nativeDV bridge/parser、默认MP4 PS-only初始化修复与native缺PS门已独立V1通过。Backend stopped-proof、Surface identity、formal producer v3与Session v2有界审核/回退亦V1通过（Session作者148tests/独立53tests+原2反例）；默认nativeDV仍unsupported。
  - runtime: 真实Session Release R1 APK07d383b0/lib7cc6f4ac已全EOS263.041667/53rows/两drop0，installed APK/lib/source外部回读通过、DropBox不变；Back Dolbyoff但cleanup pending，不宣称Session恢复/Surface释放。材料artifacts/native-dv-session-release-r1，LG Asleep/OFF/timeout30000。lib7cc6f4ac原始P5已通过Debug seek24/Home短窗及全EOS。新direct Release R1/R2均全EOS263.041667/54rows/VO与decoder drop0/DropBox不变；Back选项restore/Dolbyoff/installed APK+lib+原source回读capture通过。R2 APK97f1f20f已修正固定源16:9 viewport，材料artifacts/native-dv-release-r2；LG已熄屏/timeout30000，未提交推送。
  - acceptance gaps: R2人工颜色/亮度/流畅性未回复；direct诊断不等于formal Session或多轮生命周期。此前Release P5 SDR映射颜色正常但卡顿仍为性能失败；独立原生P5/HDR10画面/流畅性通过不迁移到demo（HDR10亮度缺）。原native Home崩溃及参数集修复依据保留在context历史。
  - next: healthy lifecycle动作/segments/schema2 v2 correction attempt1已冻结，16+16+15tests/analyze通过，Root核验5owned/17protected/10原V1文件SHA并归档，正式独立V2复验进行（原1P1+6P2及exit边界），完整review-v2 REQUEST CHANGES 2P2（slow end publication/fullscreen drain后toggle），原7直接修正闭合；原writer correction attempt2已批准两阶段provisional/certificate合同，Root external observer V4独立PASS（32tests/原4反例/失败anchor入口/真实Dart中文互验），作者v3已freeze/停止释放，Root22sourceSHA核验归档，53tests/analyze通过；应用V3独立REQUEST CHANGES 2P2，Lead接回V4双写/seek门修正，原两断言重提取PASS；53回归/analyze通过，V4已freeze/停止释放并交独立复验；第二partial实际FS无证书测试PASS；V4独立PASS，lifecycle Release R1 APKd6a56511已构建安装并回读APK/lib身份，首次实际coldlaunch startup admission拒绝（busy/current scope缺失）row0/debt，失败原报告归档，已停止；V5严格startup scope已冻结56tests/analyze通过，V5独立PASS；R2已构建安装并回读APK2523d969/lib身份，P5/SDR完整回读session63415仍运行；R2实际startup已ready两rows、Pause10Resume外部cert通过；人工细条画面（诊断面板遮挡）及页内close baseline恢复不匹配，均失败已归档；已回桌面sleep，page上下分区布局WIP/analyze通过；hwdec原值记录晚于controller初始化根因已定位，窄backend ownership修正worker实施中，待测试/freeze/独审；build draft仍false，补页内await清理、pause/seek/同URI/P5-SDR-P5/Surface/同Player Session重建；构建与外部采证工具已做mode guard草案，待freeze/独立V1。真实Backend/owner/producer+Session consumer设备诊断（窄fixture方案已接受，observer与fixture V2独立V1通过；真实Session Release R1已安装，全EOS263.041667/53rows/两项drop0，外部身份采证通过，人工待回复、系统Back清理报告pending需页内关闭补证）；Release多轮暂停/seek/Home/重入/Surface恢复、HDR/P5全屏、HDR10 demo及时序/亮度对照、P8.4及SDR回退性能；现代Vulkan设备回归仍缺。


### 2026-10-04 publication contract feasibility and preserved deadline

只读Specialist确认异步temp/flush→check→await rename不能保证可见点期限；后置certificate只能证明被引用provisional payload两个发布await返回仍在原预算内，不能证明certificate自身及时。Root已把此事实交writer先提精确方案（尚未实施）：候选不作成功，证书绑定run/request/publication/hash/真实未冻结时钟及范围；slow payload/rename/partial failure无成功凭据。为保持完整终态期限，外部还将绑定可信冷启动命令发出前host monotonic＋原run预算作为保守更早deadline，完整证书接收/验证也必须在此同钟期限内；独立observer seconds不冒充原run期限，不以限定历史payload结论替代成功验收。方案字段/seam/anchor实现仍待收敛，未改冻结产品或工具。

### 2026-10-04 lifecycle correction attempt1 freeze checkpoint

- **当前实现与审核**：lifecycle fixture v1冻结（page71541d33/helper f2053027/lifecycle f4389674/test b072ca32/原test44e4f286），作者与独立31tests/analyze/diff均通过，但独立V1正式 **REQUEST CHANGES：1P1＋6P2**。6个原文生产方法/queue主机反例失败、fullscreen为两种控制流反例，均非设备证据；完整报告/hash/logs归档 `native-dv-session-lifecycle-review-v1`。一次统一修正attempt1已交原writer `/root/native_dv_release_diagnostic`，独占lab page/helpers/tests与Flutter；核心/owner/default maturity冻结。当前7项均已进入修正：queue期限/close drain、真实idle恢复比对、page重建门、finally终止Player、Texture实际拓扑绑定、head/tail drift与fullscreen post-entry比较；限定analyze首轮2编译错（VideoController.configuration不存在、变量作用域），修正后第二轮5items exit0；queue/termination现15tests在attempt6通过（各轮失败保留），覆盖ACK/step/end晚到、active close drain、双采证失败仍dispose、页面实际close-and-exit编排及ACK失败后cleanup；晚end误分类error已修为deadlineRejected；diagnostic现12tests通过（attempt4），新增production cleanup实际baseline不匹配/读失败→debt及重建门拒绝测试；仍需健康恢复正例与真实sampler，新增实际Texture快照与fullscreen B→C→C/B→C→B共享观察对象回归；测试首轮缺ValueNotifier import失败已修（原日志保留）。新增healthy baseline production正例；真实_sampleLifecycleLocked经测试seam调用，SDR head绑定loss不debt/不采旧段，恢复新实际Texture端点后新段1row定向PASS（首跑fake epoch不一致修正，日志保留）。完整suite仍待最终回归，Texture tail代次漂移可恢复/不append旧段与foreign source→debt/0row已有真实sampler定向PASS，healthy baseline epoch单调正例也已接入。native PlatformView真实sampler head owner null→可恢复drift/0row，恢复同accepted proof五元组新段→1row，不同Java五元组→封旧段且不接纳，定向1test exit0；最终完整回归与冻结仍待完成，原独立反例待reviewer复验，不能把定向PASS当全套通过，无活Flutter测试handle，未冻结。新修正版目录lifecycle-v2已生成，仅logs，保留v1/原反例；Root build draft仍approved=false，未build/ADB。

### 2026-10-04 lifecycle exit acknowledgement boundary

最终回归15 lifecycle＋16 session diagnostic＋15 raw release diagnostic以及限定analyze均exit0（尚未冻结）。writer发现final snapshot前pop可能打断写入，final后pop失败不能再改不可变run。Root决定保持owned termination→final snapshot→SystemNavigator.pop，final明确exit acknowledgement unverified、action end scope不含Activity退出证明；pop返回或失败不能改finalized run，失败仅本地reportFailure保留具体错误，外部另核验Launcher/foreground。该生产helper pop失败测试经首轮缺JSON导入及后续final elapsed漂移失败后修正，最终elapsed/remaining固定，定向exit0；原失败logs保留lifecycle-correction-attempt1-exit-boundary，边界修正后完整回归16 lifecycle＋16 session diagnostic＋15 raw release diagnostic、限定analyze均exit0；5源SHA已生成，scoped diff及新文件空白检查通过，原ACK晚到反例原样定向复跑exit0；材料lifecycle-correction-attempt1-final-validation。尚待source manifest/报告正式冻结、作者释放Flutter与独立复核；不引入额外跨Activity协议或把ACK当退出证明。

### 2026-10-04 lifecycle correction attempt1 close test order

Writer定位旧queue反例先await run.close、后release action，与修正后的close drain pending action契约互相等待。Root允许唯一必要时序适配：保留原反例文件及失败日志，新测试start close→证明仍pending→release action→await action与close→确认final snapshot后writes稳定。增加等待drain断言，保留核心no-late-write断言；非取消Future，不允许close提前完成。close-self避免deadlock仍须单独测试，最终交独立复核。其余修正继续，未冻结/构建。

### 2026-10-04 lifecycle analyze attempt2

日志analyze-attempt2.txt：1 warning，page804 unnecessary_null_comparison，未称PASS。Root看到reopen-inside-fullscreen-after-surface-change接线与新增AppliedAdmission tests；仍待最终测试/freeze，实际入/出每段恢复另需设备证明。

### 2026-10-04 lifecycle first analyze

首轮analyze日志在build/lg-api24/native-dv-session-lifecycle-v1/logs/analyze-attempt1.txt：5 issues，curly braces两项、async BuildContext一项、无效non-null断言两项；不称analyze PASS。Root另反馈全屏仅最终重开不足以证明进入全屏后的恢复，enter/exit真实tuple变化需分别接纳新段，当前仍唯一writer实施。

### 2026-10-04 lifecycle page initial wiring review notes

Root源码回读发现8动作初版已落，但未测试冻结：P5SDRP5沿用P5 position会超出20秒SDR源；seek30仅下界会误接旧90秒状态；FullscreenRoundTrip需核对push等待语义并按实际Surface tuple变化Session reopen，预期漂移不能永久debt禁恢复。三项一次反馈给唯一writer修正，未称独立V1或设备结果。后续Root核对controls fullscreen fallback的Navigator.push未await，因此该路径push阻塞疑点已排除；Scope分支与实际Surface换代仍需验证。正确目标保留pause/seek/同URI/SDR切换/全屏/Surface/同Player新Session与await清理。

### 2026-10-04 Current State consolidation snapshot

以下为归并前的逐步状态，保留依据；其旧“尚未构建/安装”等说法不代表当前状态。

- Root当前源码回读确认sampler重复rowCount增量已移除；waitForLifecycleApplied已检查run debt/terminal/closed/deadline与同instance/generation active段至少1 row，等待器通过AppliedAdmission仅sampler append后接纳。仅WIP源码确认，不是异步tests/正式V1；作者下一补gate/seam测试与8 page动作，当前无Flutter handle，不新build/playback。

- Lifecycle真实sampler已落WIP：段token检查、旧sample/raw property drain、段首核验row后才完成Applied等待器正在实现。Root定位double rowCount（Run.appendRow与sampler record同对象各+1），writer确认删除第二增量并补单行段计数测试；schema2外部计数验证保持，不迁就错数据。页面8动作尚未完整，当前无活Flutter进程，未freeze/新build。

- Root action observer补完整main循环mock用例：同run begin→end、接纳后run变更必须失败并保留raw/receipt，14host PASS。负向设备方案已全文回读归档artifacts/native-dv-session-negative-device-plan：N1真实PlatformView不挂载→既有10s超时→同代exclude/rollback/fallback优先，N4 accepted后foreign open→dispose拒stop/restore/debt单列，现无可执行lab入口；不改核心/伪事实，不把healthy切源或OpenSuperseded当failure fallback。Lifecycle writer仍实施真实段首核验/旧pending drain与8按钮，尚未freeze。

- Lifecycle真实Session事件/SDR源接线已实际进入page与diagnostic helper WIP；Root反馈waitForApplied不能早于proof/segment接纳且需debt/deadline/current门、换段需drain旧pending reads。尚未最终测试/freeze。Root构建guard新增lifecycle新journal源码+test必须纳入批准hash清单；缺两文件的lifecycle测试清单check-only按预期exit1，未创建output/构建，日志更新artifacts/session-lifecycle-build-guard。

- Root action observer按实际journal测试契约新增ackError终态，read completion/publication原观察deadline门；12host PASS含late end读回反例拒接纳，保留raw且标outcome unknown，不重tap/重启。源码/可复跑测试/日志更新artifacts/session-lifecycle-action-observer。Lifecycle当前仅作者journal5tests通过，页面真实动作接线未完成，未freeze/构建。

- UI trigger-v2已冻结/Root复跑17host PASS，package+serial修正与before-fix日志归档artifacts/native-dv-session-lifecycle-device-runner-plan，未ADB。Root新action observer只poll指定run/label与新request，支持mutable end或独立end事件、拒重复request/terminal/错run，10host PASS/compile；artifacts/session-lifecycle-action-observer。仍为草案，需最终schema/实际UI对齐，不重tap或重启。

- Lifecycle新journal测试作者5/5 PASS（作者exec37443 exit0），当前无Flutter进程；page/真实采样/8动作尚未完成。HDR10设计define已纠正LOCAL_SOURCE必须literal、AUTO_SOURCE非Android，更新报告归档。

- HDR10对照设计已回读归档artifacts/hdr10-demo-timing-plan：Java成功PQ固定30s stream-copy是2:1几何，实际成功input无静态HDR字段、output真实static info；普通demo成功configure-input日志仍缺，不以video-params替代。Root今全回读设备76438009bytes SHA3068be37与host一致（exec79072 exit0），receipt归档hdr10-timing-device-preflight，未播放/未升亮度验收。

- 外部UI trigger-v1 15host测试/compile通过已交Root；Root反馈需匹配node package与serial严格regex，原writer正在统一修正，工具未设备执行。生命周期journal写盘已实际统一queue的WIP变化，最终freeze/tests仍待。

- Lifecycle首批新helper android_native_dv_session_lifecycle.dart已实际落盘（WIP）；Root只读反馈actionEvent复制后end不回写、ACK失败busy/debt、缺enabled entry、并发direct/queued .tmp写盘四类问题，writer修正中，未freeze/未test结论。Root collector新增schema2 histories硬界24/128/48/48、unique segmentId/orphan row/per-segment count、1..900整数budget shape校验，9host正反例通过；仍须最终writer schema对齐，不能替代设备/语义审核。

- Root collector route/mode预检查已提前到ADB之前：8host正反例通过（legacy/session healthy→schema1，session lifecycle→schema2，direct lifecycle/未知/null拒绝）。device执行器按钮8精确ID已与writer/runner统一，禁止重复tap和以launch替代Recents。另复用reviewer只读准备HDR10 exact源/timed A-B-A方案，不与生命周期writer争用源码/Flutter。

- Root构建工具新增healthy/lifecycle显式mode匹配；lifecycle必须session route、两个精确审核define且seconds1..900。旧healthy批准清单用于lifecycle check-only按预期exit1，未启动构建；syntax与反向日志/源码归档artifacts/session-lifecycle-build-guard。Writer仍独占Flutter实施，尚无新freeze/APK。

- Lifecycle writer已回方案并接schema2/session/lifecycle与8动作UI契约，保留schema1健康路径。Root外部collector草案新增显式mode→schema2与固定SDR独立SHA回读（另P5/APK/lib原检查）；py_compile通过，尚无schema2真实报告，不宣称兼容验收；最终segment/action边界校验等待writer冻结契约。草案artifacts/session-lifecycle-collector-draft。

- 后续goal推进：前轮为实质进展（真实Session EOS/外部身份采证/Back欠据）。当前已按local Team路由复用原writer实施healthy lifecycle完整动作/segments包，所有权lab page/helper/tests、独占Flutter测试，核心/owner/default maturity冻结；另只读准备外部device执行器方案。首要补页内await cleanup再退出，随后pause/seek/同URI/P5-SDR-P5/Surface与同Player Session重建。无新构建/设备动作，等待源码freeze与独立V1。

- Session R1外部采证exec24401 exit0/captureVerified=true，installed APK+lib+原P5回读绑定，53rows/EOS/error null；材料artifacts/native-dv-session-release-r1。人工观感待回复，Back的cleanup pending欠据保留，不升restore/Surface验收。已恢复timeout30000/force-stop/sleep，未提交推送。

- Session R1 EOS后执行系统Back实际返回Launcher，Dolby属性off，但after-back报告仍phase=eos/cleanup=pending；因此不能宣称Session.dispose/owned选项恢复/Surface释放已获证据。当前fixture无页面显式关闭入口，下一生命周期包需加入可等待的页内关闭再退出，系统Activity退出与Flutter路由dispose分开验收。完整EOS结构汇总无问题，采证仍在运行。

- 真实 Session Release R1 已构建安装并回读身份：APK07d383b0/lib7cc6f4ac/JAR23036e0b，run1791074230838199-809604165。consumerValidated与native RouteApplied同generation1，qcom DV/timed/Dolbyon；observer47032完整EOS263.041667/53rows/两项drop0/error null，尚待Back恢复和外部全量采证。当前人工确认已单独询问，旧SDR“颜色正常但卡顿”不迁移为本轮验收。timeout暂600000，结束恢复30000并熄屏。

- fixture-v2独立V1 PASS已全文核对/归档：原deadline/close场景+9tests=11 PASS，actual recorder EOS event/held read/row/timer链1 PASS，analyze/diff/SHA通过；关闭场景只适配新StateError接纳、原first-only断言保留，非device模拟。报告/独立logs/提取用例归档artifacts/native-dv-session-device-fixture-review-v2。Root批准精确session构建manifest（source全匹配/原JAR pin），JDK17可用/disk29GiB；尚未构建/安装，不升实机验收。

- fixture-v2 attempt1最终冻结/停止写/Flutter释放，Root逐源SHA回读归档：page62a6e47b（v1.1不变）/helper90ca103f/test44e4f286，9tests/analyze0，artifacts/native-dv-session-device-fixture-v2。独立Reviewer已接最终byte复跑原deadline/close反例与EOS生产接线，现独占Flutter；draft build源hash已更新且全匹配但approved=false，不构建/安装。

- fixture-v2 attempt1实际日志已回读：新9tests全部通过、三文件analyze0（build/lg-api24/native-dv-session-device-fixture-v2/logs），三新增为EOS during held periodic read、completion过原deadline拒绝、close drain no-next-read生产共用seams。作者仍整理最终manifest/REPORT，未freeze/独立复核/构建；原两精准反例需Reviewer在最终byte上复跑，不能以9绿替代。

- Root补单段Session报告汇总工具并通过4 synthetic checks：正常binding、缺counter保持unknown、重复EOS拒绝、generation不配对拒绝；源码/结果/SHA归档artifacts/session-summary-host-validation。明确row.source为accepted proof复制而非外部重新还原实时source/Surface，结构/counter不升显示/性能验收。fixture-v2三P2修正attempt1仍在writer实施，无新APK。

- fixture-v1.1正式独立V1 REQUEST CHANGES报告已落且归档：三P2，deadline与close为原文提取方法级精确动态反例；EOS为生产控制流确定序列，未完整动态复现，不混称三项都实机复现。六tests/analyze0/保护SHA保持；完整REVIEW.md与review-decision在artifacts/native-dv-session-device-fixture-review-v1。一次统一修正attempt1已执行分派，build approval仍false。

- fixture-v1.1独立V1收齐REQUEST CHANGES三P2：EOS在周期read中到达后row虽eos但timer未停止；读取completion越原deadline仍接纳（精确反例late-value/exit1）；closing后pending完成又发第二read（精确反例first,second/exit1）。原6tests/analyze0不足覆盖。独立原文提取+最小Player替身反例/日志已归档artifacts/native-dv-session-device-fixture-review-v1（非device反例），完整报告待落。Writer已收到一次统一修正attempt1，独占Flutter，三文件范围/新v2目录，不构建/安装。

- 作者最后冲突开关修正导致page由072bdd67变62a6e47b，manifest已同步；旧freeze原样保留，新版以v1.1归档并SHA核验。writer已明确停止/Flutter释放，Reviewer现独占Flutter正式审新版（首查旧manifest mismatch已解释，不隐去）。Root准备session draft build manifest approvedForBuild=false，全部source哈希匹配，尚不构建。Reviewer已指出EOS during periodic sample异步链候选确定缺陷，等待完整正式报告再统一处理。

- 真实Session fixture-v1作者冻结材料已落并Root回读SHA核验归档：page072bdd67/helper319b143c/test19d51acc，6tests/analyze0，artifacts/native-dv-session-device-fixture-v1。测试仅planner/identity/gen/生产IO queue，不覆盖整条延迟native read→close/Session disposal失败；首轮断言失败未存raw日志如实注明。等待writer明确停止与独立V1，不构建/安装，defaultunsupported不变。

- 外部Session observer终态校验已补并通过6项mock host测试：deadline→wall-limit、closed→closed-without-EOS、EOS独立终态；schema字符串/错误source/错误label均拒绝。无实际ADB/playback；源码/原始logs/results归档artifacts/session-observer-host-validation，避免正常有界停止误判或重启。fixture作者首次analyze0；首次3tests exit1仅错误取ordinary selected maturity，已改为native candidate断言，生产planner不改；async生产seams仍在补，未冻结/构建。

- 下一生命周期SDR控制源设备/host全字节绑定完成：exec34886 exit0，/data/local/tmp/media-kit-sdr-control.mp4 12177758bytes/SHA664ad7d5，ffprobe AVC/1280x720/BT709/20s，与host相同。归档artifacts/session-sdr-control-preflight，供后续固定P5-SDR-P5动作使用；未改变初版P5-only allowlist/未播放，不声称恢复验收。

- Session候选设备前置采证完成：exec35692 terminal exit0，原P5全289758635bytes/SHA DACF匹配，power Asleep/OFF、battery100%/28.2C，未新安装/唤醒，材料artifacts/session-device-preflight。只读生命周期下一包已完成并归档artifacts/native-dv-session-lifecycle-next：pause/seek/Home/同URI/P5-SDR-P5/fullscreen/同Player新Session的expected/forbidden/proof/missing明确，初版单segment不代替循环验收。后续SDR固定控制源加入既有授权范围，实际SHA先核验；方案中的“批准动作包”不新增用户许可要求。fixture当前仍writer实施/待tests与freeze。

- Session构建门新增route绑定：旧direct approval不能用于--route session；session approval必须覆盖真实Session/helper/page三关键文件。syntax与旧R2 approval负向check-only已验证（预期exit1/无构建），脚本/验证归档artifacts/session-diagnostic-build-route-guard；fixture页面接线初稿已出现，测试与freeze尚待。

- fixture WIP第二次即时源码核对：真实Player lock与budget已加入，EOS逻辑仍把terminalObserved混作pathCleared而拒绝合法completed/非空path，且close仅等sampleFuture未等超时后仍存活property read；已发精准修正与测试要求，尚未冻结/独立审核/构建。设备只读预检online、battery100%、29.3C，未唤醒/安装。只读生命周期方案另在整理：初版单segment不能证明同URI/切源/Surface恢复多轮，后续须actionId/sessionId+accepted历史明确分段；完整目标不缩减。

- HDR10后续对照事实整理完成（artifacts/hdr10-demo-next-check）：当前FF输入MediaFormat未显式写color aspects/static info，Java成功轮保留Extractor aspects且codec自行输出真实static info；差异不是已证明原因。P5 timed成功不迁移HDR10；后续固定同源boolean/timed/boolean，保持普通HEVC/native_dv关闭与默认boolean，原nativeDV option owner不泛化。本轮只读，未改native/app默认设置。真实Session fixture初稿已落，Lead早检要求修共享Player锁、Map tuple比较、IO串行/晚关闭/原采样预算/codec与Session generation尾验，待冻结独立V1，不构建初稿。

- Session observer-v1独立V1 PASS：独立160 tests/analyze0/owned与protected SHA一致；callback仅forTesting，被动精确consumer事实，不变默认maturity/route，不重置原deadline，重入与双层exception contain通过。独立报告/日志归档artifacts/native-dv-session-observer-review；正式fixture implementation与后续APK/device仍未完成。Root session/direct构建/observer/collector工具已syntax检查及归档artifacts/session-diagnostic-host-tools，尚未执行新Session候选。

- Session observer-v1作者冻结：Session e9c0fd32/test f87253ac，新增12+原148共160 tests通过、analyze0；源码/manifest/原始日志归档artifacts/native-dv-session-observer-v1。原v2 policy/helper不变，独立V1正在复跑，未构建/安装该版本。Root构建工具新增显式session/direct选项，collector新增隔离Session报告路径与route校验（syntax通过），正式fixture仍在实施。

- 真实Session诊断fixture方案已接受并实施：Session作者仅写被动consumerValidated observer及独立测试，lab作者仅写页面/新fixture/helper测试；真实Backend/owner/producer/consumer与硬能力门保留，固定P5诊断单独绕过maturity，默认unsupported不变。observer固定原deadline/fresh generation，capture异常不改变route；正式Session实机证据尚缺。用户本轮回复明确对应旧package:media_kit SDR映射：颜色正常但卡顿，既有性能失败保持，不转移到R1/R2原生DV。

- R2 direct Release全片与Back清理/外部采证完成：observer exec23019、collector exec80875均terminal exit0；54rows/eos263.041667/VO0/decoder0，source/player/entry/epoch/完整Surface与actualqcomDV配置endpoints一致，DropBox前后字节不变。Back report=shutdown restored owned option pair、Dolbyoff；installed APK97f1f20f/lib7cc6f4ac/sourceDACF真实回读绑定，captureVerified=true。正确16:9预先viewport与两截图归档artifacts/native-dv-release-r2（全观察JSON/receipt/源码页面/identity）。无人工回复，不升显示/亮度/流畅验收；不是formalSession/多轮生命周期。LG已force-stop/timeout30000/复核Asleep+OFF，未知既有forward未动。

- R2已安装/installed APK+lib回读一致并实际播放：APK97f1f20f/label lg-p5-native-release-r2-20261004，runId1791070104147803-0eebdc40d82f53b6da79ecdbe53082e6，16:9 viewport截图正确、early rows nativeqcomDV/timed/drop0/error null。外部observer exec23019仍running，目录build/lg-api24/native-dv-release-r2/observation；须等EOS再Back/restore/capture/熄屏，勿以观察timeout重启。R2人工问题已单独发出待回复，R1问题未答不迁移验收。formal Session真实诊断窄fixture只读设计已交原Session作者，defaultunsupported不改。

- Release V2独立V1 PASS并构建/安装R1：APK ab2a8706/lib7cc6f4ac/原sourceDACF设备回读一致；direct原生qcomDV/timed/Dolbyon，从0至EOS263.041667，54rows所有drop0/source/entry/epoch/Surface/config endpoints稳定、DropBox字节不变。Back实测report=shutdown restored owned option pair且Dolbyoff；外部collector真实captureVerified=true。原始资料artifacts/native-dv-release-r1；人工回复尚待，非formalSession/完整生命周期。R1竖屏viewport拉伸已由截图+3840x2160/SAR1:1确认；Root只修固定源诊断页预先16:9 Surface约束/analyze0并构建R2(APK97f1f20f)，安装中待新轮观察。
- 构建清单纠正：Session v2 manifest采用nested owned，R1初次build-guard漏读三个Session文件，已补post-build固定SHA核验并如实标记metadata；R2完整pre/post guard包含三文件。Session归档冻结源码/identity也已修正，默认nativeDV仍unsupported，R1directdiag未运行formalSession。

- Release六项修正版v2冻结待独立V1：page79b37f79/helper44a9b340/testbd121f80，15诊断seam tests+39 owner/Surface/config回归通过、owned analyze0/diff/format过。REPORT/manifest/6原始日志与三冻结源码归档artifacts/native-dv-release-diagnostic-v2。writer已停止；独立Reviewer复核6修正中，未构建APK/实机验收。

- Root已补有限Release JSON观察脚本 build/lg-api24/observe-native-dv-release.py（syntax通过，未运行）：固定候选label/每launch runId、≤300单调rows、10秒外部采样、335秒观察期限、EOS/error终点及finally receipt，不依赖VM；仅报告观察，不视为性能/人工验收。collector rowCount新增严格int门，尚未设备采证。Release writer当前源码已接startup锁内身份/restore锁/remaining-budget/page admission/EOS失败标记，测试与freeze仍未结束。

- Session v2独立V1 PASS：两条原反例原样复跑通过、53新tests/analyze/diff通过、3冻结source与9个producer/backend保护SHA一致。原deadline/microtask接纳/fresh generation门已闭合本次确定缺陷；报告和独立日志归档artifacts/native-dv-session-policy-v2。仅合成策略/接线，不是实机Session/HDR/性能。Release六项修正仍在实施，构建等待其freeze+V1。

- Release完整独立V1 REQUEST CHANGES已归档artifacts/native-dv-release-diagnostic-review-v1：2个P1（initial stop前无锁内身份门、最终restore无sharedLock）+4个P2（page waiting-bound disposal屏障、closed后late Timer/subscription、EOS采样失败热循环、sampling中途属性读取未使用剩余总wall预算）。8utilitytests/analyze独立通过但不能排除生产流程缺口；未编造实机反例。原writer已收到六项一次修正包并开始处理，Session v2独立复核另行继续。

- Release独立V1已核对生产缺陷（正式报告/精准反例正在整理）：initial idle锁外读取后stop未锁内比较，foreign queued open可能被stop；startup最后report await后仍可晚注册timer/subscription；page等待initialBound后未检查disposed可晚创建diagnostic；sample catch未设_sampleFailed导致EOS finally热重试；最终options.restore未持Player共享锁。已交writer等待完整报告后一次统一修正，原8utility tests不能证明生产生命周期。新APK构建暂未准入。

- Session修正版v2冻结：显式microtask接纳边界后按原deadline/current检查，再Session消费await后fresh generation门。148tests（53新增+95回归）与analyze0，原两反例通过；仅补await门曾仍失败的日志也保留。Session eb4d3377/helper acfc79a5/test3d11992d，档案artifacts/native-dv-session-policy-v2；独立V1待复核，不是APK/实机验收。Release三文件冻结8局部tests/analyze0，独立V1审查中；Root已准备受reviewed source manifest与钉定JAR约束的Release构建脚本，未运行构建。

- Release诊断Lead复核发现startup/dispose竞态：shutdown未等_startFuture，late begin/open可能在清理后继续。writer已确认并在实施closed边界检查+startup完成屏障再resolve pending/owned stop/restore；外层timeout仅报告pending，不取消或并行恢复。此为未冻结包的修正，不代表运行时已通过。

- Session包第一轮冻结（50新增+95回归，定向analyze0）独立V1发现代际隔离缺口：consumer末端同步检查后到锁Future返回之间可被supersede；实际Session反例中旧review继续触发planner，新generation最终结果仍被coordinator拦截，未声称错误视频接受。原writer正在修复helper锁await后与Session消费await后generation门，并补精确microtask反例；未获V1、未构建新APK。Reviewer最初Player facade/native推断已查明本fork typedef Player=NativePlayer而撤回，不算缺陷。
- 用户的Release P5反馈仍为颜色正常、卡顿，性能未通过。新的原生DV Release诊断尚未冻结/审核/安装，不能将此前独立探针或Debug零掉帧转为Release流畅验收。

- Release外部采证collector已实施syntax/help通过（未设备执行）：tool/android_hdr_probe/collect_release_diagnostic.py，固定appfiles report路径，installed APK/arm64 lib/全原源bytes回读SHA绑定、candidate label/runId和≤300rows校验，保存raw JSON/独立receipt，source read120秒watchdog；captureVerified仅采证不接受phase/性能/显示。档案artifacts/release-diagnostic-capture。
- Release writer已确认使用真实currentBoundOutputIdentity五元组，不以nativeSurfaceActive=true作Surface准入（旧成功Debug字段false）；默认5秒采样/1..30interval、独立wall1..300秒+≤300rows，EOS非重入terminal安排，owner begin/restore不做可导致rollback竞态的外层硬timeout，挂起/债务及FFI不可取消如实记录。Session writer59tests先过，额外补consumer配置末端读取/跨review-retry预算，均未最终冻结/审核。

- formal nativeDV producer v3独立V1 PASS：42producer tests+两条原精确反例独立通过，analyze/diff过，9源码/保护SHA与freeze一致；两端config/hwdec及tail首次pin缺陷已闭合。helperfe56c86b/testd8530b89，实际backendb136a3e6 branch接入；档案artifacts/native-dv-review-facts-v3含冻结5文件/manifest/log/review。只producer VM/static，不代表Session/新APK/实机HDR/性能；Session+Release诊断writer仍在实施。

- producer第二/最后Worker修正版v3冻结：helperfe56c86b/testd8530b89（其他3保持b136a3e6/ab3b6e89/e40af183），首次head或tail有效配置/hwdec立刻pin，即使需下一轮重采样；95tests/analyze0，作者两条原Reviewer反例PASS，独立v3复核中。epoch+1与protected owner confirmForCleanup既有严格门一致，迟到其它FILEloaded导致+2在owneropen已拒绝；属既有可用性限制，本producer不放宽。

- formal producer V1请求变更P1：首snapshot config读后track读期间config消失可返回旧证据，v2末端重读config/hwdec已修复原反例（92tests/analyze0），但同Reviewer再复现tail首次A未pin→下一轮B被接受P1。writer第二次最小修正中：两端任一首次合法config/hwdec立即pin，即使该轮需重采样；若再同类问题交回Lead，不能第3次重修。当前producer未审核通过，不构建正式包。
- Session方案已批准且独立writer实施：outer review8秒monotonic acceptance窗口从delegate之前开始，按serial/plan/facts关联；consumer用remaining在实际NativePlayer sharedLock读取当前source/entry/epoch前后稳定并比evidence、controller完整Surface tuple，拒绝同URI pending entry替换，不adopt；超时不能取消FFI/producerfuture，只能拒绝晚结果。每generation native一次，nativeHDR+DV统一最多2个HDR尝试，failed-native excluded跨重分类保留，ownership/source/debt abort；test seams仅forTesting，defaultmaturityunsupported。
- Release rawnative诊断方案批准且独立writer唯一labpage/commonhelper/tests实施：默认false编译define、固定原源lg-dv-p5-2160p路径、等待真实Surface/初始ownedidle、复用已有typed owner和backend static identity helpers成对native_dv=1/timed/回读及ownedstop→restore，禁Session/换source/自动二源冲突；最多300条串行指标externalappfiles JSON(path_provider/原子写/无需权限)，无native_dv_diag高频日志，APK/sourceSHA仅外部绑定。未freeze/审核/build/设备，Kotlin不改。

- formal nativeDV reviewFacts已冻结待独立V1：backend b136a3e6/open_plan ab3b6e89/review a23c4106/evidence e40af183/test34be7a5c；35new+旧合计88tests通过/analyze0，producer helper真实接nativeDV分支，普通gather保持。旧owner5a8003cf/controller42f1613d/e4c5dcdb/parser81912b8b未变。仅VM/静态，未实机，证据build/lg-api24/native-dv-review-facts。Session有界回退独立writer已接设计包（唯一Session/test所有者），确认前不写；默认maturityunsupported不变。

- 新候选原始P5从0至EOS诊断完成：exec58397 terminal exit0，54个5秒snapshot，generation3/path守恒，EOS263.041667/VO0/decoder0，实际qcomDV MIME/native-active配置；DropBox前后字节相同，PID17260终点存活。APK0a6f53a7/lib7cc6f4ac/原源DACF回读绑定，材料artifacts/native-dv-default-ps-full-eos。仅rawDebug计数/配置/连续采样证据，未formalSession/Release/人工画面/面板HDR验收。已force-stop、timeout30000/remove18181/sleep，复核Asleep/OFF。

- 默认MP4修正版已独立V1 PASS并构建安装LG：lib7cc6f4ac/JAR23036e0b/APK0a6f53a7，feature-on demux_lavf链接新API、无新API/Vulkan硬符号未解析。原始DACF素材回读SHA匹配，两个codec extra135(18ec)/CSD109(a374)，重建codec2首AU24秒PSfront；一次seek24→Home3/return3/play14窗口无新DropBox，PID17260活，time38.083/VO0/decoder0，截图正常及qcomDV/native-active配置事实。仅rawDebug短窗口，不声称正式Session/全生命周期/Release/面板HDR验收；关键材料已存artifacts/native-dv-default-ps-runtime-original，独立runtime证据审核中。
- 新候选从头至EOS连续诊断现已结束exit0：exec session58397（已terminal），build/lg-api24/native-dv-default-ps-full-eos/run.py，每5秒snapshot、限300秒、原path/generation守恒、finally采DropBox/pid，前10秒mediacodec/VO0，最终EOS263.041667/VO0/decoder0。run-end已归档，清理并核验OFF完成。
- formal nativeDV reviewFacts实施包方案已批准：独立writer拥有backend/open_plan及new evidence/helpers/tests；fixed owner opened identity与匹配FILEloaded epoch+currentcontroller完整Surface五元组，短sharedLock内配置事实before/after校验，总reviewdeadline含FILE/output/config waits，strictapi1DV/name/active/hwdec；typed failure保留ownership/debt cause。普通review保持，Session策略未接/defaultmaturity仍unsupported。APK0a6f53a7是该writer开始写之前的冻结包，不能把后续源码视为已安装。

- currentBoundOutputIdentity只读基础已冻结独立V1 PASS：real42f1613d/stube4c5dcdb/helper5fd44eb7/test74965987；Reviewer独立identity/intent/ledger17tests过、diff过，analyze仅HEAD既存491/525两处info。使用当前nativeHandle完整owner tuple+current intent/available/live/noinflight/no release/failure/dispose；只证明读取当下身份，跨await同tuple不能证明期间无同身份重绑定，也不证明可见/HDR。formal Session尚未接，默认nativeDV maturity仍unsupported。
- PS-only修正版冻结aefcddab/dc508b89/0ff48255/a3cf5626；独立新版日志已通过defaultparser6314、dual12628/all21fault以及单轨12fault/EOF/EAGAIN/interrupt/buffer/cap/avctx同步、0decoder opens，最终V1结论待回传。nativebuild manifest20项已核对并approvedForBuild=false门控，尚未执行。

- FF PS-only V1发现并修正P2 no-op小预算边界：新增零heap preflight先确认实际PS类型/ID，再检查repair预算；待冻结回归。Reviewer旧快照默认parser独立全6314包byte/side-data/PTS/DTS/duration/flags/order/pos守恒、12allocation失败、EOF/EAGAIN/interrupt/buffer/64cap/avctx同步均过且decoder opens=0，不能覆盖新修正版；真实双轨仍待。Lead准备单slot保留其余JAR字节的打包脚本与绑定installedAPK/lib/原素材SHA且finally采DropBox/pid的Home复验脚本，均syntax过但未运行。
- 正式Session输出身份基础实施中：独立writer唯一拥有Android controller real/stub与新增helper/test，readonly currentBoundOutputIdentity仅stableavailable/live/currentintent/完整tuple/noinflight/未disposed返回；不改bind/release，不解锁nativeDV maturity。APK构建必须等writer冻结避免编译中源变动。

- 默认MP4接线/native缺PS拒绝独立V1 PASS（ce0bdbc8/5cc306fb/ec95d1e2）：Reviewer独立重跑5脚本和diff，common.c/h保持。公开PS-only API单轨6314包与12项allocation失败作者已通过，双轨真实容器/default parser及末端失败待补；NOBUFFER校验移到缺PS候选确认后以保持0=无需处理。API未冻结，尚未新整库/APK/实机，不能声称Home修复；LG当前Asleep/OFF。

- 默认MP4接线/native缺PS拒绝包已冻结待独立V1：demux_lavf ce0bdbc8、meson 5cc306fb、mediacodecdec ec95d1e2；512项实际branch、真实HEVC parser/CSD109、初始化缺PS configure/start=0及API24 feature0/1通过。FF公开PS-only接口全片守恒仍在验证，Reviewer补默认parser路径与多轨发布末端alloc失败；尚未构建下一Android候选。

- 默认MP4缺口方案已选并实施中：FF新增avformat_complete_initial_dovi_hvcc专用PS-only公开入口，不加结构布局字段，正常队列读/缓存、原codecpar与已initavctx全部预分配后事务发布；有候选却预算/EOF/EAGAIN不完整返回负值，0仅无需处理。mpv仅auto=-1/default mp4.skipinfo且无skip_lavf_probing调用8MiB/64包预算，FF尊重probesize（首AU1.3MiB需完整读取，最多一包越扫描预算仍原样缓存后终止）；explicit yes走既有完整probe，no/nostreams不暗改。FF native缺真实PPS→SPS→VPS链在configure前拒绝，普通HEVC/SDR不变。两writer scope分离，初始算法已核对，尚未冻结/V1/构建。
- Lead独立default-ps builder已准备并syntax通过：额外重编mpv demux_lavf，临时config feature-on且canonicalFF头优先，最终必须链接新API；不改prefix。源manifest/worker冻结与V1未完成，未执行。

- 原源Android候选复验FAIL：APK0481f0b2/so cdde3afa已打包安装，05:37:54 Home后仍libdovi SIGABRT；两新codec extra23/noCSD，decoder2首24s IDR无PS。mpv默认mp4 skipinfo=true + auto probeinfo直接跳过find_stream_info，FF初始化补全未执行；此前V1/host通过不等于demo接线。需有界PS-only默认MP4集成，不能把skipinfo排除当最终成功。只读Specialist已接根因/方案，证据artifacts/native-dv-demux-ps-runtime-original。结束force-stop/timeout30000/remove18181/sleep。

- 初始化PS修复V1 PASS（demux71bab550，其余3files冻结）；Lead完整本机avformat计数wrapper验证full人工齐codecpar/video_delay2时23→135/opens0，预算128/NOBUFFER保持23/opens0，missing仍135/opens1；首AU0 bytes及PTS/DTS/flags一致。实际host binary1373ae03清单已更正并记人为条件。独立Android库cdde3afa/21766320B已打包APK0481f0b2并安装；原源Home复验失败，默认MP4未执行该补全，详见最新失败记录。证据artifacts/native-dv-demux-ps。
- Lead接管backend stopped-proof P2：begin必须传不可变空源proof，普通stop在同Player lock内capture，native stop保存confirmed，prepare首次写前核对proof/player/path/entry/epoch；外部loaded/pending/cancelled/不同Player新5测试零写入。49tests/analyze0/diffcheck通过，SHA b1274f2e/5a8003cf/2365d68b，独立V1 PASS（49tests复跑、analyze0、diffcheck）。实际NativePlayer/Session/codec和显示仍未验。maturity仍unsupported。

- 初始化PS补全V1进行中：冻结demux1592b3f8/helper5bd7431c/header33b3a731/Makefileaff1f817，host真实AU0重建135B hvcC SHA18ec7f7e与封装对照一致。Reviewer发现P2：pending绕过原all-info退出后无条件try_decode_frame，可额外打开软件HEVC decoder，违反helper-only范围；候选不构建/不实机验收，writer先只读提出PS-only与原需decode探测分流。host helper/gate通过不能证明完整demux probe控制流。

- 连续采样工具实机验证完成（30s）：APK552ed51a及原素材dacfd045设备回读hash匹配，全部采样path/generation保持，实际路由mediacodec_embed/mediacodec/boolean，vd-lavc-o空、hdrSessionReport null。该诊断包forced embed，不能充作SDR Texture基线或正式nativeDV/HDR验收；raw记录及REPORT在artifacts/playback-window-tool-verification。采样期间无seek，结束force-stop/timeout30000/remove18181/sleep已执行。

- 连续采样准备：只读capture_playback_window.py已syntax/--help通过，存档artifacts/playback-window-capture/，尚未实机执行。绑定设备APK/素材回读SHA、当前path、每次采样generation及请求起止时间；失败或身份变化保留raw错误。仅Debug VM诊断，不代替Release验收、不将generation解释为Surface代次。LG ADB当前仍online。

- Backend新P2修复范围经Lead核对：沿NativePlayer共享非重入lock绑定open→filename/id捕获/pending保存及stop→stopped捕获，内部显式synchronized:false，FILE_LOADED等待在锁外；新增wasm stub编译接口parity。writer拥有原3文件+stub，测试需真实Lock/barrier执行共用backend捕获方法并覆盖同URIpublicopen捕获前/释放后替换。raw command/主动synchronized:false不受该锁保护，管理会话禁止并发绕锁源变更，不能宣称全局安全；maturity仍unsupported。实现和V1未完成。

- 性能证据只读复核：build/lg-api24/api24-fixed-p5-later.json在81.833s记录VO累计696、decoder drop0、mediacodec-copy、3840×2160 NV12，report为P5→SDR/Texture/gpu-next。快照未绑定APK hash、缺连续时序/CPU/GPU耗时；不能由VO计数断言GPU根因，也不拼接seek/fullscreen/Home不同阶段计算drop rate。下一轮需要固定包/素材身份与低频连续采样。
- Lead已准备build/lg-api24/build-native-dv-demux-ps.py独立候选构建脚本（Python syntax通过，尚未执行），会同时重编canonical codec诊断5 TU、format demux/helper和mpv6 TU，独立archives重链；不覆盖prefix。需待writer冻结及V1后执行。

- 正式参数集补全包已启动：仅FFmpeg demux初始化与必要helper，先窄范围MOV/HEVC/validP5/缺PS hvcC，在现有probe预算内采真实PS并保持lengthSize/样本/DV配置，发布前一次补元数据；精确算法及动态PS/中段/skipinfo边界待核对，尚未实现或宣称修复。

- 实际输入闭环新增：同diag APK552ed51a/so75d335/verbose非trace，原源Home重建decoder2 extra23/csd_not_submitted/首AU24s NAL19,40,62无PS，queuehash同AU/flags0，参数集au48才到；PID13671 04:49:25同libdovi SIGABRT。补hvcC源decoder2 extra135/csd_submitted109、首AU前置32,33,34+原19,40,62，flags0，恢复38.083/VO0/无新DropBox，actualqcomDVactive true。两轮decoder2前96AU均连续捕获，ringDropped0；AU序号跨epoch连续，预算外非全片证据。输入证据独立V1 PASS，Reviewer从原MP4重建AnnexB核对两组192AU：仅首/下一IDR（AU1/49）补真实109B参数，其余94AU完全同；窗口内IDR/SEI/type62载荷不变但RPU语义未知；CSD和BSF前置同时变化不能各自单独定因果。证据artifacts/native-dv-input-runtime-{original,hvcc}/。
- Backend成对owner复审：原迟到FILE_LOADED恢复P2静态链已修复，40tests通过；新增P2：open返回后独立捕获entry之前，外部同URI加载可被误认own。当前版本不得验收，writer先只读设计Player串行load/entry身份绑定。helper手工rebind测试不算backend open→stop→reset动态覆盖；actualcodec/session与实机事务未验。

- 有界FFmpeg输入诊断V1 PASS；Lead独立重编common.h全部5个使用者并重链成功，so75d335/APK552ed51a已用于上面的实际输入对照。构建脚本及all-users日志在build/lg-api24。

- 最新对照：纯hvcC补集候选7d05238a与显式诊断开关V1 PASS；设备回读hash一致。同old02407/低error日志/默认detach/seek24.041/Home相同步骤，两次fresh process均恢复到38.208/38.083s、VO0、无新增DropBox，截图有视频。相对原源同配置复现崩溃，强支持参数集可达性假设；后续diag已补实际CSD/AU闭环，仍不能宣布正式fix或生命周期全过。证据artifacts/native-dv-home-hvcc{,-repeat}/。

- 范围：LG API24能力、hdr_lab兼容、SDR/HDR10/P8.4/P5/nativeDV路由、性能和生命周期。目标仍in_progress；未授权提交/推送，不覆盖其他Darwin工作。
- 设备：LGH870DS42e27764 / LG-H870DS / Android7 API24 / Adreno530 / arm64 / 1440×2880。显示声明HDR10+DV，无HLG；HEVC Main/Main10/HDR10、DV profile32与4K60均是能力声明，不等于性能。
- 人工验收：独立MediaPlayer→SurfaceView官方P5画面正常流畅；独立MediaCodec→Surface HDR10/PQ画面/颜色/流畅性正常，亮度未确认。先前MediaPlayer/PQ实际黑屏事实保留，原因未定位。ADB HDR黑截图不替代实际观感。
- Release demo P5 SDR映射：用户最新人工回复再次确认“颜色正常，但有卡顿”，颜色通过、流畅性失败；该观察绑定SDR映射测试，不作为原生DV或HDR亮度验收。copy输出nv12，不能宣称保持10bit。P8.4 SDR映射也未完成性能验收。
- 已验证兼容增量：Vulkan两个1.1硬导入改动态core/KHR解析，API24加载A/B通过；API29 P5 HardwareBuffer探针门控；SDK24/25 Texture gpu-next+mediacodec-copy独立依赖、SDK<28 GPU HDR dataspace明确不可行。48项原route/session测试及V1通过；现代Vulkan设备运行回归缺失。
- 原生DV诊断：FFmpeg默认关闭native_dv P5/单层/Surface门控，统一mpv/qcomDV启动；Java timed/boolean/timed正文A/B/A支持该LG条件下timed释放呈现关联。mpv默认boolean/显式timed选项已实现，隔离timed候选动态P5及全片EOS263.041667/零计数drop、seek/暂停、P5→SDR复位已采证；不替代Release性能或人工验收。
- 配置能力桥：新库6152c7b5/APK d44750bf实机JNI API1，SDR→P5→SDR实际MIME/codec/active依次AVC/false、qcomDV/true、AVC/false，mode boolean→timed→boolean。仅当前codec配置事实，不代表显示。内部严格parser4tests/analyze/V1 PASS。
- 生命周期失败：同codec同Surface seek24.041可持续；同Surface新codec重建出现PTS倒退与持续VO掉帧（后段2→75）。Home恢复PID8115/10729崩溃；仅先停轨D仍PID11574崩溃；低trace默认C仍PID12028崩溃。均MediaCodec_loop→libdovi CpuLutManager→parseRPU SIGABRT；先停轨/降trace不足以修复，根因未定。
- 最强待证假设：官方P5空hvcC23B/arrays0；后续IDR19的VPS/SPS/PPS在前一非key包尾。fresh decoder可能跳过参数集。离线291包NAL/配置/hash证据已归档，原素材不变，RPU语义依赖unknown。本机BSF保持NAL字节不直接证明Android实际输入。
- 纯规划nativeDV增量已V1 PASS：strict HEVC/DV P5/compat0/ELfalse、display1、硬件DV profile32、bridge1门控，独立于GPU P5pipeline；DVtransfer、route native_dv1/timed/RPU保留。未知EL保留null。66定向+19backend/session回归通过。成熟度仍unsupported，默认不可选。
- 未完成执行链：backend成对option ownership正在实施，受控stop/open身份迁移设计尚需验证；session实际codec身份绑定/有界失败回退未接，不能把diagnostic native-dv-open当正式路线。
- service独立日志接口及显式inputDiag开关已V1，diag包已安装并完成原源/补集对照；纯hvcC资产V1与设备hash核验通过，播放证据见上。
- 采证构建约束：FFmpeg AV_LOG_INFO在mpv映射MSGL_V；新diag包需MEDIA_KIT_ANDROID_VERBOSE_LOG=true，不启用逐帧trace。已有低日志默认包为error级，不能误当会捕获diag。
- SDR暂停/seek/Home/Back重入、真正Material全屏进出有独立证据；HDR/P5全屏和Surface恢复仍未过。诊断generation是open serial，topologyGeneration非Java Surface代次，日志时间是Dart接收时间。
- 证据根目录：本仓archives/experiments/artifacts/lg-hdr-20261004/；完整构建/连续采样位于 ~/src/media-kit-build/lg-api24/。收尾已force-stop demo、timeout30000、移除本轮tcp18181、熄屏；初始亮度255/manual不变，未知既有tcp54700 forward未动。下次先唤醒/解锁并核验。



### 已被实际输入闭环更新的前序状态

- 有界FFmpeg输入诊断V1 PASS（3 source SHA绑定）；Lead独立构建已重编common.h全部5个使用者并重链成功，产物native-dv-input-diag-build/libmpv.so，APK/实机输入采证尚未进行。构建脚本build-native-dv-input-diag.py及all-users日志在build/lg-api24。
- 最新对照：纯hvcC补集候选7d05238a与显式诊断开关V1 PASS；设备回读hash一致。同old02407/低error日志/默认detach/seek24.041/Home相同步骤，两次fresh process均恢复到38.208/38.083s、VO0、无新增DropBox，截图有视频。相对原源同配置复现崩溃，强支持参数集可达性假设；尚无真实CSD/首AU诊断闭环，不能宣布正式fix或生命周期全过。证据artifacts/native-dv-home-hvcc{,-repeat}/。
- 输入采证正在实施：FFmpeg有界默认关闭诊断初版API24 syntax及host ASan/UBSan通过，额外分片/总日志预算收紧中，尚未V1/构建。service独立日志接口已V1；新增显式inputDiag开关纳入ownedoption回读/恢复，限定analyze/pycompile通过待V1，未安装。纯hvcC对照7d05238a已验证dvhe/dvcC/mdat及6314NAL/时间/key保持、1053stco必要重定位，已上传LG并host流式回读hash一致；资产V1审核中，未播放。


### 2026-10-04 LG task ledger before reconciliation

- [ ] LG-H870DS API24 HDR能力检测与 hdr_lab 移植
  - status: in_progress
  - context: archives/conversations/lg-h870ds-hdr-demo-20261004.md
  - latest (规划增量): strict nativeDV realizer与DVtransfer/option模型完成，66定向+19backend/session回归通过，maturity仍unsupported、V1待结论；离线291AU证据已归档，不代替Android输入实证。
  - latest (输入调查): 离线发现empty hvcC与关键帧前非key包参数集布局；NAL保持封装对照、有界FFmpeg输入诊断实施中。新独立诊断日志接口静态通过待V1，未改变播放行为。
  - latest (正式接线准备): 内部codec configuration parser完成，4tests/analyze/V1 PASS；planner nativeDV独立门控与离线AU采证进行中，backend/session执行仍未实现。
  - latest (低日志复测): 关闭trace默认Home仍PID12028同栈SIGABRT，排除高trace为必要条件；离线AU/参数集采证及正式Session设计继续。
  - latest (生命周期对照): 仅开启先停轨开关仍复现PID11574同libdovi SIGABRT，不能作为修复采纳；继续查中途重建输入/参数状态，低日志复验待做。
  - latest (能力桥实机): 新库6152c7b5/APK d44750bf已安装；JNI API1及实际SDR→P5→SDR MIME/codec/native-active状态切换、boolean→timed→boolean恢复验证通过，配置事实不替代显示验收。
  - latest (复核): 用户确认Release P5 SDR映射颜色正常但卡顿，性能失败；原生DV同Surface重建有PTS倒退/掉帧，Home返回复测PID10729在libdovi同栈SIGABRT，生命周期未过。新静态/实际能力桥库6152c7b5构建与headless验证通过，实际codec/JNI及正式Session接线待验。
  - acceptance: runtime codec profiles/Main10/DV及显示能力报告；demo可运行与SDR/HDR10/P8.4/P5/DV明确路由，暂停/seek/重入/Surface重建；原生HDR与人工画质、流畅性分开验收。
  - latest: 原生MediaPlayer官方P5人工验收通过；HDR10独立MediaCodec→Surface PQ直出获用户确认画面/颜色/流畅性正常，亮度未确认；先前MediaPlayer黑屏差异未定位。libmpv Vulkan加载修复及API29探针保护已实机验证；SDK24/25 Texture路由已用gpu-next+mediacodec-copy独立依赖，SDK<28 GPU dataspace候选明确不可行，48/48测试、lab analyze与V1通过。当前源码Debug包集成矩阵与暂停/seek/Home/Back重进已采证；P8.4/P5 SDR映射有画面但4K性能未过，Release demo人工确认P5颜色正常但卡顿，性能未通过。统一Player原生DV候选已启动真实qcomDV/Dolby on、72s零计数掉帧，但截图旧SDR色条，实机显示待回复；正式native DV能力/路由尚未集成。独立Java release API A/B/A正文对照：timed可见buffer、boolean无buffer，mpv隔离timed候选已恢复动态P5和1920×1080视频buffer/0drop，人工确认及正式能力/策略接线待完成。正式默认boolean/显式timed诊断双选项及SDR恢复已实机验证；Home返回后libdovi输入RPU处理SIGABRT，生命周期未通过，分离seek/decoder/Surface对照待做。
  - next: HDR10原始PQ直出人工画面/颜色/流畅性已通过，补亮度与demo embed对照及先前MediaPlayer黑屏差异；Release默认渲染SDR已显示，P5及4K性能待验证；P5性能修复、HDR→SDR复位、全屏/同engine Surface重建及现代Vulkan回归。



### 2026-10-04 accumulated diagnostic state before reconciliation

- 纯规划nativeDV增量已完成，66/66 planner/classifier tests；Lead额外backend/session regression19/19通过。realizer strict来源P5/HEVC/compat0/ELfalse、display1、hardware DV profile32、bridge1，不依赖GPU P5pipeline；route显式native_dv1/timed/DVtransfer/RPU保留。EL未知保留null。成熟度仍unsupported，backend/session未接，V1审查中。
- 离线AU包已归档artifacts/native-dv-au-offline/（291包，起点与20–28s及边界）；原素材前后hash/size/mtime不变。所有采样IDR19，后续参数集在前非key包尾；本机BSF NAL字节序列保持。RPU语义依赖unknown，Android实际输入尚缺。封装对照继续生成核验。

- 新离线线索（待输入实证）：官方P5 hvcC23B/num_arrays0，首AU含VPS/SPS/PPS，24s IDR仅19/40/62，参数集位于其前一非key包尾。mpv重建复制原codecpar、hevc_mp4toannexb不缓存后续参数集，可能漏集；不能直接定根因。正在制作NAL字节保持的封装对照，FFmpeg默认关闭有界AU/queue诊断实施中。
- 诊断采集准备：service新增native-dv-input-logs独立ring4096与dropped计数，不读decoder属性、不用普通300条日志环作为完整AU证据；attach时清除，open/reinit保留跨实例输入日志。限定analyze/pycompile/diffcheck通过，独立审核待做，尚未构建/安装此增量。

- 正式backend准备增量：新增内部AndroidMediaCodecConfiguration schema parser，严格API int1/MIME/codec/active及DV一致性；inactive允许未知codec空；仅配置事实，调用者仍须绑定媒体身份。4项测试、限定analyze/diffcheck通过，独立V1 PASS（parser81912b8b/testbb51b9bd）。尚未接入backend，不改变默认路由。纯nativeDV realizer门控包与离线AU证据包正在执行。

- 低日志默认C复测仍失败：保留old02407库，关闭CODEC_TRACE_LOG与stopfirst（baseline默认顺序）；PID12028于04:22:14新增同libdovi CpuLutManager→parseRPU SIGABRT。高trace不是此崩溃必要条件；仍不能据调用栈定责vendor或格式。证据artifacts/native-dv-home-low-log/。离线AU/参数集检查与正式Session设计包正在执行，均不操作设备。

- 先停轨对照D失败：同old02407库/trace配置，仅开启既有stop-video-before-platform-detach；APK ac7d64cd。Home快照vid=no/wid0，返回新wid2099398；PID11574仍于04:19:00 libdovi同栈SIGABRT。不能将该开关认作修复；后续调查恢复输入/参数状态与低日志复验。证据artifacts/native-dv-home-stop-first/，完整采样build目录同名。

- 最新能力桥实机闭环：6152c7b5库只替换控制APK的libmpv.so，APK d44750bf，签名校验通过。JNI capabilities nativeDvBridgeApi=1；实际SDR→P5→SDR回读依次为video/avc/qcom AVC/active false、video/dolby-vision/qcom DV/active true、AVC/false；释放模式boolean→timed→boolean。仅证明当前codec配置，非显示/流畅性。证据artifacts/native-dv-facts/；正式Session接线及生命周期问题仍未完成。

- 最新验收：用户确认当前 Release demo 官方P5 **颜色正常、存在卡顿**；SDR映射颜色通过、性能失败。独立原生MediaPlayer的流畅验收不可转移到demo。
- 新对照（旧选项库02407ed0、诊断Debug包）：同Surface seek24.041后持续播放；同Surface vid no→1重建恢复画面但输出PTS倒退、持续VO掉帧（后段2→75），性能未过。Home→返回→play复测进程10729退出，DropBox新增2026-10-04 04:09:23 SIGABRT，MediaCodec_loop→libdovi CpuLutManager::precomputeDoviLuts→parseRPU，与先前8115同栈。根因未确认，不能仅归因厂商或timed release。C证据保留于 ~/src/media-kit-build/lg-api24/native-dv-home-controls/。
- 能力桥增量已实现并V1：FFmpeg导出实际MIME/codec/native-active，mpv提供静态android-native-dv-bridge-api及实际android-mediacodec-info；JNI/Java/Dart静态字段nativeDvBridgeApi独立于P5管线。新库6152c7b5已构建，headless API24验证旧库属性缺失、新库API1、无decoder时actual unavailable；实际codec/JNI验证见顶部最新闭环记录。正式HdrSession nativeDV路由仍未接入。
- 本轮A/B/C使用高日志Debug诊断，不作为Release流畅验收；Dart日志时间是接收时间，不能推算真实codec启动耗时。实际生命周期问题和Release SDR卡顿分别跟踪。

- 目标仍在实施：LG API24的解码/显示能力、hdr_lab兼容、SDR/HDR10/P8.4/P5/DV明确路由及生命周期；未授权提交/推送。原生HDR和人工观感必须独立验收。
- 设备 LGH870DS42e27764，LG-H870DS / Android7 API24，msm8996pro/Adreno530，arm64，1440×2880。系统HDR列表[2,1]（HDR10/DV），面板HDR标志1；无HLG声明。解码能力声明HEVC Main/Main10/Main10HDR10、4K60 query true，不等于4K60性能。
- 官方DV P5 4K24：独立MediaPlayer→SurfaceView获用户“画面正常，播放流畅”确认，Dolby模式on。仅这条原生路径获验收；HdrSession nativeDolbyVision仍unsupportedStrategy，不能说demo原生DV已实现。
- HDR10/PQ：原生LG播放器、独立MediaPlayer在4K/1080p均黑屏；用户确认实际黑屏。修复后HdrSession走mediacodec_embed仍截图黑、解码时间前进。原因未定位；route/nativeHdr与report.verified不能替代显示验收。
- libmpv在API24加载失败已严格A/B定位并修复：Vulkan两1.1硬导入改实例动态core/KHR解析；candidate导入仅少两符号，包内lib SHA256 626122e9177db4ac9b2b1c79e0187bb9ffb185d3d64e7f70d3728405cb744633。canonical ~/src/mpv 四文件未提交；补丁与build说明在本主题artifacts。现代Vulkan设备运行回归尚缺。
- hdr_lab MainActivity原生P5 ImageReader/HardwareBuffer探针新增API29门控；当前源码Debug已构建/安装，LG上通过service p5-probe实际返回UNSUPPORTED，无高API调用崩溃。
- 已实现API兼容：已知SDK<26的Texture sdrDirect/toneMapSdr保持gpu-next并选择mediacodec-copy/独立dependency；SDK<28的GPU HDR dataspace候选返回gpuHdrDataSpaceUnavailable；embed与SDK0不受这门控影响。Session mismatch按对应解码依赖排除，最多重开一次；P5pipeline gate/RPU逻辑保留。V1静态审核PASS，Lead复跑planner+session 48/48，lab analyze无问题。
- 实机集成包 ~/src/media-kit-build/lg-api24/hdr-lab-api24-session-fixed-debug.apk，JDK17/arm64、candidate JAR SHA256 6bdc8592de6578f63022d973e364532e7b7196b394c8b9c4bdc0204ad6963441。用本地SDR源和HDR_TRANSACTION+SERVICE_PROBE defines，启动Intent关闭Impeller。未知默认Impeller与Release包验收仍未完成。
- 当前集成矩阵：SDR实际gpu-next+copy、无hwdecMismatch；PQ native embed黑；P8.4→HLG decoder facts→toneMapSdr copy有画面；P5 pipeline分类5/compat0、dynamic=true、RPU不剥离、toneMapSdr copy有画面，但4K慢/掉帧。P5约81.8s计696 vo drops，Dolby模式off；不是原生DV，不声称10bit（copy输出nv12/average-bpp12）。Release demo人工确认颜色正常但有卡顿，性能未通过。
- 已纠正早期推断：连续截图证明SurfaceProducer和legacy SurfaceTexture均可主动呈现变化帧，不据启动单张黑屏全局切换legacy。配置对照保持隔离。
- 暂停稳定回读121.958s；seek20随后resume回读20s；Home自动暂停21.375s，返回仍暂停并保留可见画面，play可恢复。Back关闭旧main/isolate；等关闭完成后重进创建新isolate与SDR画面。首次过早am start与异步Back竞态/随后start -W timeout均记录为环境/时间观察，后续VM与画面确认重进；不把am start结果单独算成功。HdrVideo全屏/Same-engine显式Surface重建尚未单独验证。
- Debug服务探针仅Android+Debug+显式define，经过页面原换源逻辑，generation/identity/busy防串证据、UTC错误日志最多300。代码common/android_service_probe.dart，命令工具tool/android_hdr_probe/demo_service_probe.py。禁用VM auth仅用于本地ADB诊断启动；收尾移除forward并停止应用。
- 原始证据本仓artifacts；完整构建/连续截图/JSON/源ffprobe/测试日志 ~/src/media-kit-build/lg-api24/。主机43GiB空闲（最近复核）。设备初始亮度255/manual未改，timeout初始30000、临测300000，收尾恢复30000并熄屏。

- Release/default-renderer：当前源码SDR包已安装，默认启动连续5次截图有变化画面；不再需要Debug禁用Impeller参数。Release P5包已安装默认启动、有可见画面；用户确认“颜色正常，但有卡顿”，颜色通过、性能未通过。
- 用户再次确认独立原生P5探针“画面正常，播放流畅”；该确认对应MediaPlayer→SurfaceView，不对应mpv demo的SDR映射。

- 新MediaCodec→Surface对照：显式指定qcom HEVC后4K PQ实际configure/drain成功，passthrough/PQ/SDR标签三组各约8.8s/262–264 scheduled帧，截图仍黑，但用户随后报告刚才看到了HDR10视频；随后单独passthrough重播获用户确认画面、颜色、流畅性正常；亮度未确认，不能据截图判为实际黑屏。PQ输出含BT2020/PQ及非零真实HDR static info。这些结果说明配置已携带色彩aspects和静态元数据，尚不能据此定位先前黑屏原因。SDR标签实验不做tone mapping，不构成SDR画质验收。此前finder返回null的4K轮未configure，不计入显示比较。证据：~/src/media-kit-build/lg-api24/codec-surface-byname-matrix/。

- 应用户要求单独重播HDR10 passthrough原始PQ直出，未切换其他模式；30s全片解码EOS，input902/output903/scheduled902，lateOver50ms=0，maxLate3264us，stop/release/extractor释放成功。此为解码调度与资源证据，用户确认这轮画面、颜色、流畅性均正常；亮度不确定（观察时已停在片尾），不能把scheduled当面板呈现计数。报告：~/src/media-kit-build/lg-api24/hdr10-human-replay-session.txt。

- 原生DV接线新证据：同一MediaCodec→Surface探针无需修改，指定qcom Dolby codec后官方P5 configure/drain成功、Dolby on且截图可见；MediaExtractor输入video/dolby-vision/profile32/level32、csd-0为空。输出BT2020/transfer3，不能从输出标签推断SDR转换；本轮调度/截图证据不代替新路径人工验收。报告native-dv-codec-session.txt；需FFmpeg原生DV MIME/profile/AU封装及统一Player路径实现。

- 生命周期补测包hdr-lab-api24-surface-rebuild-debug.apk（SDR控制+HDR10错hint）构建/安装，最终session为SDR/copy，画面可见、0drop；只有最终快照，不足证明前序PlatformView实际teardown或Surface generation变化，重建验收仍未完成。后续控制时机复测已显示Material controls：实际全屏按钮进入横屏全屏，seek2/play后连续帧变化，Back退出回普通页面继续播放，snapshot7.13s→10.63s/vo drop0。同一probe generation1；证据sdr-fullscreen-steady-{0,1}.png及enter/playing/exit.json。仅SDR路径全屏进出已证，不能代替HDR/P5全屏或Surface代次交接。
- 原生DV实施第一增量正在canonical FFmpeg两文件加入默认关闭native_dv选项，保留统一mpv Player、valid P5单层/Surface门控；V1静态review通过，独立候选lib/JAR构建完成，动态UND392与API24基线完全一致；实际DV播放和集成未完成，默认路由尚不启用。完整后续包括actual MIME/codec/nativeactive能力、HdrSession候选/恢复预算/合法空option恢复、跨源及Release人工性能验收。

- 统一Player原生DV候选运行：稳定诊断入口c0d691459217/CLId2ca448ca79a经V1，Debug APK候选JAR23dc8a7d。explicit native-dv-open P5后FFmpeg日志video/dolby-vision/profile0x20/真实Surface/qcomDV started successfully，hwdec=mediacodec、Dolby on，14.4→72.2s时钟前进、VO/decoder drop0。但ADB截图始终旧SDR色条10.1s，已问用户实际是否动态P5；尚不能接受显示/性能。首次native请求时SDR初始加载尚未完全稳定，出现h264 native gate失败日志，后续P5真实codec成功，须按path/decoder日志分段，不能用请求返回即时snapshot作成功。证据native-dv-candidate/p5-snapshot-{1,2,3}.json、p5-dolby-property-*与surfaceflinger。正式能力/active property/session接线仍未做。

- 连续trace补证：统一Player已持续调用MediaCodec release render=1（约50.7s附近），而SF仍保留1280×720 SDR缓冲区；零drop/时钟不能替代画面呈现。Java独立探针timed/boolean/timed初轮只观察前6s，可能受片头黑场干扰，不作因果判断。seek20短轮三组scheduled均0，未到可呈现目标帧，不计入释放API显示比较；改从头播放至24s正文采证。

- 正文release API A/B/A已完成：timed两轮约24s截图有蓝色视频、视频activeBuffer1920×1080；boolean同PTS段截图黑、视频activeBuffer0×0；三轮均Dolby on且lateOver50ms0。支持该条件下release API与buffer呈现关联，尚未验证mpv timed候选，不作普遍DV厂商要求。证据artifacts/dv-release-ab-body.md及build目录dv-release-ab-body/。

- mpv timed独立候选实机恢复P5真正动态画面：APK仅替换so，V1通过；lib507070de77cc、APK b905d6a3e825。原生qcomDV、Dolby on、同wid2099318、持续timed trace、SF1920×1080、0drop；截图不再旧SDR色条。已请求人工颜色/流畅性/亮度确认。正式计划保留默认boolean，只由原生DV路线显式选择timed，后续能力/路由/复位/生命周期仍待实施。

- timed候选全片P5 EOS263.041667s，completed=true、VO/decoder drop0；seek20后恢复23.25s动态图，暂停24.416667s稳定、resume到27.708333s；P5→SDR vd-lavc-o恢复合法空、Dolbyoff、3.03→6.70s连续色条变化，再P519.75s可见视频。此为隔离全embed timed诊断验收，不替代正式选项/Session或人工画质。正式canonical VO新增global option mediacodec-embed-render-mode=boolean|timed、defaultboolean，每flip缓存更新，V1通过（910c1aaa5c05）；完整默认保留/显式timed包正构建，正式nativeDV能力和session未完成。

- 当前正式选项/诊断包已构建安装并验证：默认SDR boolean；native-dv-open设置timed+native_dv1后23.708s动态P5/0drop；owned timed事务请求boolean被拒，选项不变；普通open恢复boolean+合法空vd-lavc-o，SDR4.133s可见。Dart双选项事务c214b64e3840/CLIda6fdfdbd873经V1/analyze0。见native-dv-option-runtime.md。
- 原生DV Home重建验收失败：活动播放23.458s/wid1050814→Home24.041667s/wid0/暂停→返回wid1050830/暂停→play24.291s；随后PID8115于03:31:21 SIGABRT，libdovi precomputeDoviLuts→parseRPU→MediaCodec queue input。不是timed release栈，不能仅据vendor栈认定厂商bug。输出PTS倒退和拆卸期间软件fallback/RPU警告是线索；环形日志缺最终队列/首AU，需同Surface decoder重建/同codec seek/真正Home分离对照，再比较vid=no先拆开关。新启动PID8879仍存活；旧crash系统提示框不是第二次崩溃。
- FFmpeg runtime facts单文件81e7398e7328已V1：readonly/export schema marker1（READONLY default初始化跳过，runtime init显式赋1）、自有MIME/codec名/active，未知名称为空；失败/close/fatal/flush负值清空、EAGAIN/EOF/成功flush保持。尚未构建/安装或接mpv正式属性；android-native-dv-bridge-api须查schema default，实际android-mediacodec-info须经decoder wrapper线程锁读取，后续桥接/session待实施。


### 2026-10-04 earlier diagnostic snapshot

- 目标：先验证设备 HDR 显示链，再实施 hdr_lab API24兼容和 SDR/HDR10/P8.4/P5/DV矩阵；未授权提交/推送。
- 设备：LGH870DS42e27764，LG-H870DS / lucye，Android7.0 API24，msm8996，Adreno530，arm64，1440×2880；fingerprint lge/lucye_global_com/lucye:7.0/NRD90U/172921900e77a:user/release-keys。
- Display Binder getDisplayInfo(0) HDR列表[2,1]，HDR10+DV；亮度500/200/0.5 cd/m²。面板 is_hdr_enabled=1，hdr_capable=1。无HLG声明。声明不等于实际面板输出验收。
- 原生LG播放器：官方P5 3840×2160@24，NuPlayer MIME video/dolby-vision，OMX.qcom.video.decoder.dolby-vision，656帧/0drop，dolby.vision.playback=on；截图有可辨画面。SF输出1920×1080 RGBA8888，存在 CPU Lut Generation / Pixel Processing线程；不能据on推断10bit或面板原生DV。force-stop后playback=off。
- PQ Main10 3840×1920@29.97：LG播放器OMX.qcom.video.decoder.hevc，440帧/0drop，SF硬件层Y_CBCR_420_VENUS_UBWC / CS9；截图黑，用户确认手机实际也是黑屏（本轮可见输出失败），CS9具体含义未核实，不宣称HDR激活。
- hdr_lab已有release APK（Oct3，versionCode2086 minSdk24 targetSdk36）安装成功，但启动白屏、Activity存活；关闭Impeller的Intent实验仍timeout，不能认定原因。设备logcat所有buffer无输出，未改变日志系统配置。
- MainActivity P5探针入口已加API29门控（ImageReader usage overload API29，getHardwareBuffer API28），尚未重建/设备验证。API24纯buffer探针须另实现，不能让整类访问高API。
- 当前主机空闲43GiB（本轮复核），此前空间不足已解除；可继续当前源码的完整Flutter构建。独立轻量探针已完成runtime报告及P5人工观察。
- 设备初始亮度255/manual、screen_off_timeout=30000；本轮仅临时改timeout=300000，结束须恢复30000并熄屏。

- 原生独立探针runtime报告：HEVC profiles 0x1/0x2/0x1000（Main/Main10/Main10HDR10），MainTier level0x10000，4K60 areSizeAndRateSupported=true（声明而非性能）；DV profile0x20 level0x8。报告文件 probe-pq-report.txt。
- 独立MediaPlayer→SurfaceView播放P5，连续position增长、状态栏Dolby图标、用户确认“画面正常，播放流畅”；仅该官方P5素材通过观感，不外推其他profile。
- 白屏加载根因已直接复现：将原APK libmpv打包到原生探针自己的nativeLibraryDir，System.load失败：cannot locate symbol vkGetPhysicalDeviceQueueFamilyProperties2。静态检查同时发现vkGetPhysicalDeviceProperties2缺导出。不是仅猜测Flutter渲染。
- 独立探针源码tool/android_hdr_probe，API24/JDK17构建及签名通过；MainActivity API29门控 compileReleaseKotlin 通过（JDK17，offline，target-platform=android-arm64，使用本地钉定JAR，排除Flutter AOT重编）。

- PQ黑屏在独立MediaPlayer→SurfaceView也复现（4K30、1080p30），有rendering-start与持续position/解码帧增长，不是仅LG播放器UI；1080p采样454frames/0drop。原因尚未定位，不能判定整个设备HDR10永不可用。

- Vulkan兼容修复：canonical ~/src/mpv 四文件动态解析core/KHR，缺接口仅拒绝受影响Vulkan路径；V1静态审核PASS与resolver mock五分支PASS。二Android编译单元语法检查通过。只编二新对象并重链到/tmp，不覆盖derived源码、对象或libmpv；derived原strip后与已装APK字节一致SHA e0d607af946a2f0a53e77aa02143c8075288d51a53fd6f74b5f1ff58fbf7d166。
- 修复candidate动态导入对比仅删除目标二符号，无新增；原生探针打包自己的lib目录后System.load成功（probe-candidate-library-report.txt）。修复前同APK探针失败→修复后成功，加载门槛闭环。
- 已将旧release APK仅替换libmpv安装，路径~/src/media-kit-build/apks/lg-hdr-lab-vulkan-loader-candidate.apk；Gate MainActivity新代码不包含在此A/B包中，勿将代码compile成功当已安装。进入横屏说明越过MediaKit.ensureInitialized；仍黑界面，待Debug/Dart状态排查，不算demo播放通过。
- Debug APK /tmp/media-kit-lg-elf/debug-aligned.apk 是10月2日旧debug仅替换libmpv，不是当前源码重建。关闭Impeller后已显示Flutter下载页，说明该诊断包越过初始化；尚无demo实际播放验收。

- 当前源码Debug重建/安装成功（JDK17、arm64、本地candidate JAR SHA256 6bdc8592…）；包内libmpv与candidate同SHA256 626122e9…。已包含API29探针门控，固定本地SDR源，不再等待联网下载。关闭Impeller后Flutter播放器UI可见；VM对象显示1280×720 nv12/BT709、position19.966s、duration20s、completed=true。初始截图黑，点击UI后显示正确末帧色条：连续呈现仍未通过，正在比较SurfaceProducer与legacy SurfaceTexture。构建/截图/VM证据 ~/src/media-kit-build/lg-api24/。

- SurfaceTexture对照包当前源码构建/安装通过：hdr-lab-legacy-texture-debug.apk，仅define MEDIA_KIT_ANDROID_SURFACE_PRODUCER=false有别。启动后不点击即截图显示6.733s色条，VM playing=true/position6.566s；证明这一路有主动呈现，默认SurfaceProducer黑屏现象需进一步精确对照。尚非HDR/流畅性/生命周期通过。VM evaluate因没有compilation service失败；getObject只读字段可采样。Flutter attach未接通已停止。

- 2026-10-04追加连续帧对照：两种Texture均不点击即连续出变化画面，启动单张黑屏不证明SurfaceProducer故障，撤销该推断，不改默认开关。连续采样在~/src/media-kit-build/lg-api24/{legacy,producer}-continuous-*。
- 新增Debug+Android+显式define服务探针ext.media_kit.hdr_lab.probe，经过页面_openSelectedSource而非raw Player.open；generation/身份/busy/UTC日志隔离，V1修正两项后PASS，analyze无问题。素材从SDcard直读Permission denied（manifest未请求旧存储权限），shell复制到/data/local/tmp后可读；失败不计矩阵。
- Texture baseline vo=gpu + hwdec=mediacodec-copy：SDR1280×720连续变化0drop；PQ1080/4K、P84、官方P5可出画面，但PQ4K约10s vo掉201，P84约10s观察仅4.5s播放，P5约10s掉1。观察窗口不是全片验收，不宣称原生HDR或流畅性。输入Main10在copy输出中为nv12，不能宣称保持10bit。矩阵JSON/截图sources.json在~/src/media-kit-build/lg-api24/texture-matrix/。
- HDR session当前源码baseline选择gpu-next + mediacodec，在API24实际hwdec=no（软件解码），SDR与PQ降级为hwdecMismatch；该失败与平台缺AImageReader/AHB一致。正在设计SDK分支的copy兼容方案，不能仅改hwdec字符串而保留错误依赖/复核逻辑。


- 本轮收尾：测试demo与codecsurface probe已force-stop，timeout恢复30000，移除本轮tcp18181 forward并熄屏。另有tcp54700→18181既有forward，归属未知未动；亮度255/manual保持原值。下轮先唤醒/解锁并重新建立VM连接。

### 2026-10-04 lifecycle v3 publication contract approved

- Lead批准原writer attempt2两阶段合同：end-provisional → end-certified；archive/latest两份provisional写入Future均成功返回后，以同一未冻结run Stopwatch读取完成上界，严格小于原deadline才产生receipt。receipt自身发布及时性仍unverified，不能将rename admission当作及时成功。
- 证书绑定run/request/action/publicationId/deadline及完整payload；携带sorted-key-json-utf8-v1 canonical文本作为精确SHA输入，解析后必须等于payload，拒绝重复key和浮点。Root外部publication_contract.py及7初始host测试通过，尚未集成observer或独立验收。
- 外部完整证书接收期限必须锚定冷启动ADB命令之前的host monotonic + 原run预算，再绑定新的runId；禁止tap前重置原期限。Root负责observer/anchor，writer负责原五文件及串行Flutter。尚未构建、安装或实机播放；整体目标继续。

### 2026-10-04 external certificate observer integration draft

- Root实现run_deadline.py冷启动锚点草案（未执行ADB）：读取旧run，force-stop后在唯一am start之前记录host monotonic及原预算，绑定新schema2/label/run/budget，host bootsessionuuid防跨重启沿用。观察器必须传入该anchor，局部观察期限取min(local, original)，证书接收/解析/验证后再次检查期限，不接受旧end。
- 新证书/期限验证与原17 observer测试已按end-certified适配；首次34执行全部通过（包含导入测试类造成7重复，已改模块导入避免重复，待最终重跑）。仍需launch异常/延迟证书端到端host测试、真实Dart输出互验及独立审查；不可用此草案启动实机验收。未构建安装提交。

### 2026-10-04 external observer v3 host replay frozen

- 31独立测试通过（原17适配+7证书+5anchor/launch+2真实CLI轮询）。健康provisional→certificate可接受；原run预算1s而observer预算120s，第二次读取在101.1且原deadline101，迟到证书不接受。冷启动测试证明host锚点在唯一start命令之前，失败start无run绑定且无重试；均为mock host，未操作LG。
- 外部工具/测试/日志以SHA冻结于media-kit-build/lg-api24/session-lifecycle-external-tools-review-v3-input，待独立V1；应用writer仍在实施，不并发Flutter。launch CLI尚未独立审核，不用于实机。

### 2026-10-04 prior lifecycle v2 Current State retained

- **当前实现与审核**：lifecycle v2 correction attempt1已冻结，作者停止写入/释放Flutter，Root核验5owned SHA、17protected SHA及10原V1文件字节一致，归档native-dv-session-lifecycle-v2。最终16＋16＋15 tests/analyze/diff/whitespace通过；manifest绑定page436d39e6/diagnostic086ed2cc/lifecycle1f54b742/lifecycleTest7c6253f0/diagnosticTest31ab3563。正式独立V2复验已交原reviewer，独占Flutter，针对原1P1＋6P2、必要close测试时序适配和final-before-pop边界核验；复验已发现新增动态反例：slow end publication跨deadline先暴露end、内存随后deadlineRejected无法撤回外部观测（queue-and-late-end.log），原SDR无Java owner、native head loss、actual restore拒复用及双采证失败page终止4反例生产重演通过（sampler-cleanup-replay.log）；原ACK/close动态用例通过，新late end publication反例仍失败。新增fullscreen pending-read drain越deadline后仍toggle动态反例失败；真实page ACK failure终止beforepop复演PASS（fullscreen-and-pageclose.log）。完整review-v2已落盘REQUEST CHANGES 2P2，原7直接修正/6原动态反例闭合、独立47tests/analyze/SHA通过；Flutter已释放。原writer已接correction attempt2，独占5lab文件/Flutter，先提出publication合同方案，输出v3，核心/default maturity冻结，不能宣称通过。Root已刷新22-source构建draft但approved=false，无新build/ADB/实机播放。

### 2026-10-04 external observer review-v3 correction attempt1

- 独立V3 REQUEST CHANGES 3P2/4生产反例：Python bool/int/float宽松相等削弱payload类型绑定、前序cat失败误认不存在致旧run可用新期限、fresh evidence I/O失败error anchor仍可用。报告SHA00fd1b16bf79a7dc9eefc1e5cfe7e6ffd6e9ffd70062336bd461633a05aa9a88及原失败保留。
- Root correction1：payload和decoded均值域检查/递归严格类型相等/唯一canonical编码，receipt deadline严格int；前序读取失败直接停止且不启动；锚点要求completed=true且无error，仅fresh evidence写成功后绑定run，失败清空run并completed=false。首次无前序报告不宣称fresh，当前LG存在历史报告可按严格方式采证。
- 原4反例未改重跑通过，32hosttests通过，含nested bool/float/noncanonical；更新真实Dart中文canonical互验SHA bc516208d2ae850ef95046e2a9204e3a1562cff1f437b5d8274afd847e717ffd通过。新输入SHA冻结external-tools-review-v4-input，待独立复验；无ADB/构建安装。

### 2026-10-04 external observer V4 independent PASS

- 已读完整报告并归档V3失败/V4复验/input，V4 REVIEW SHA6e7669fc5956db0d4f7f47e47e15f588bd4e4d70f9a262cf44dc5f265d90009f。9冻结文件SHA匹配，原4反例未改PASS、32tests PASS、失败/未完成anchor两个入口拒绝且零ADB，真实Dart中文payload互验通过。仅host工具合同；首次无历史报告仍明确拒绝，当前LG历史报告存在但实际启动未运行。
- 应用v3日志all-tests显示53PASS/analyze5items无问题，作者仍在整理原反例/冻结，不用未冻结结果授权构建。设备/画面/亮度/生命周期仍未验收。

### 2026-10-04 lifecycle V3 freeze and independent review dispatched

- 作者停止/释放Flutter；Root核验22source（5owned+17protected）完全匹配，保存sources与lead-source-verification。REPORT SHA4deb264cf464c6309f2cae0991195e098da3fa4e091ac9ddf8588bdde9d64428，manifest1301051bd062e4bf0e5312e33699f7f559026462e9f5d7744f5478654bbf1249。
- 原reviewer独占Flutter正式复验V2两P2/真实publication queue+两page toggle+53tests/analyze/sourceSHA，按新证书协议解释必要适配、不缩小原成功期限。构建draft仍false，无新APK/ADB。

### 2026-10-04 lifecycle V3 build draft refresh

- Root将22-source draft中5owned哈希更新为已冻结V3，附freeze manifest SHA1301051b；approvedForBuild仍false。build-native-dv-release.py --route session --mode lifecycle --check-only确认RuntimeError Not approved for build，未创建输出/未调用Flutter。独立应用reviewer已确认running并等待50s超时，未因此重启或重复复验。

### 2026-10-04 application V3 independent interim counterexamples

- Reviewer当前仍running/Flutter未释放，报告未冻结；53tests和原slow/fullscreen三replay通过，但新增两确定P2：首cert后历史any-certified导致第二provisional跳过archive却发双写receipt；actual page seekAndObserve订阅cancel await1100ms越1s后仍player.play。实际FS/action与page提取反例日志已保存，初始harness compile失败也保留。
- 原writer已两次修正，Lead决定完整报告/资源释放后接回处理，不再交原作者第三次修正；当前不改正在审核的源码，不构建。

### 2026-10-04 Lead takeover lifecycle V4 correction

- 完整V3独立REQUEST CHANGES 2P2报告SHA3716ecf1fefad84c4cef15390db55e5e3fdfd4d8b41b38c1bc2145313078a51a已读/归档，reviewer停止并释放Flutter。Lead接回writer，不给原作者第三次修正。
- 仅page/lifecycle两文件：当前provisional writeNow(requireArchive:true)明确双目标，普通后续certificate报告latest-only不变；Pause10Resume和Seek90Then30内每个pause/play紧前fresh gate。新V4 replay从当前完整helper/实际页面函数与调用片段重提取，仅源码版本更新、原断言保持，真实FS第二动作归档与seek迟到禁止play两tests PASS。首次错误cwd无pubspec失败日志保留、正确cwd重跑通过。
- V4完整53tests已启动session60316，尚未最终freeze/分析/独立验收；build仍false，未ADB。

### 2026-10-04 Lead lifecycle V4 frozen

- Root仅改page/lifecycle，53tests/analyze5items/diff通过，原two negative assertions重提取PASS，实际FS first healthy/first partial/second partial共3PASS；第二partial在历史cert后当前archive含provisional且无当前receipt/cert。protected17SHA匹配。V4 REPORT/manifest/source copies/原wrongcwd失败与正确重跑日志已冻结归档；Root停止写入并释放Flutter。待独立复验，无build/ADB。

### 2026-10-04 prior V3 freeze Current State retained

- **当前实现与审核**：v2独立复验REQUEST CHANGES 2P2（slow end publication/fullscreen drain后toggle），原7直接修正和6反例已闭合，47tests/analyze/SHA通过；原证据保留。attempt2作者正实施v3：end-provisional/end-certified、archive/latest写完后的真实单调时钟上界、绑定完整payload/hash；全屏两toggle前fresh admission。v3已冻结，53tests/5-item analyze通过；Root5owned+17protected SHA与manifest一致并归档。REPORT4deb264c/manifest1301051b，作者已停止/释放Flutter，正式应用V3独立复验已交原reviewer，核心/default maturity冻结；approvedForBuild=false，无新build/ADB/播放。

### 2026-10-04 V4 review wait and device state

- reviewer确认running，50秒等待未完成，未重启；Root独立只读ADB目标仍device，power Asleep/OFF/timeout30000，归档lifecycle-v4-preflight/device-state.json。无唤醒/安装/播放；待审构建draft保持false。

### 2026-10-04 lifecycle V4 independent PASS and build authorized

- Lead已读完整V4 report SHA7e14d7360f03d1eff4e9272522bd817bba0bf325bb6063400926513d5d287276并归档；原两P2闭合，6独立反例/正负控制＋53tests/analyze5items/SHA前后无漂移，资源已释放。仅host代码/协议验收。
- Lead在用户既有实施/安装授权内批准固定源/库/V4源码的session lifecycle Release构建，另存v4-build-approval=true，原draft保留false；无新device验收声称。构建使用JDK17临时env，不改全局配置。

### 2026-10-04 lifecycle Release R1 built and installed

- V4独立PASS后按22-source/JAR固定清单构建成功，APK d6a56511421b2f5fd2f3828ddcc3847ab3f216f9cf76ba0dcf0feb36d9fcabc8，lib7cc6f4ac/JAR23036e0b；session lifecycle模式/预算900s，label lg-p5-session-lifecycle-r1-20261004。使用临时JDK17，无全局配置修改。
- adb install -r Success；pm path后pull installed-base.apk全字节SHA与候选一致，zip lib SHA一致。receipt/build身份归档。未启动/唤醒/播放新版，设备/画面/动作仍待验收。下一步冷启动前hostanchor与freshrun绑定，然后8case外部采证/人工观察。

### 2026-10-04 lifecycle R1 actual coldlaunch startup rejected

- 唤醒Awake/ON、再次MENU后keyguard=false。已审coldlaunch工具实际运行绑定fresh1791084707955361-145531241（前run1791074230838199-809604165），原hostbudget900s completed=true；报告身份正确。
- 实际初始open失败：startup failed Bad state Action admission closed before session-open-initial-open，debt=true/terminated-with-debt/rowCount0。Root源码确认startup直接_lifecycleOpenSource，但ensureActionSideEffectAllowed要求busy/currentAction/request，仅runAction设置；startup未进入此作用域。53hosttests未覆盖真实startup接线，不称decoder/播放失败或验收通过。原始report/anchor/start证据归档。
- 已force-stop并KEYCODE_SLEEP结束失败实验。下一步新增严格一次性startup admission作用域，保持用户动作门不放宽；源未改，需fix/test/独立审查后新build。

### 2026-10-04 V5 startup scope correction frozen

- 实际startup缺busy/current scope根因已按页面源码确认；Lead新增一次性runStartup固定startup identity/request/active-settled，保留原deadline/closing/debt和动作白名单。页面实际initial lifecycleOpenSource包在scope内，成功后再enable。正常/重复/late/close drain回归3项加入项目suite，总56PASS/analyze5无问题/diff通过。仅page/helper/test3文件，17protected匹配，V5冻结sources/manifest/log归档，Lead停止释放Flutter；待独立审核，无新build/设备播放。

### 2026-10-04 V5 review resource failure and retry

- 独立reviewer首轮usage limit错误是terminal，不把未完成当PASS。未产生review-v5目录。Root live account usage ordinaryUsageAllowed=true/primary0，故同冻结版本重试一次，agent确认running后50s等待超时；没有以观察超时重启，没有购买或消耗reset credit。主任务未自审替代独立gate，未新构建/安装。

### Prior V4 Current State retained

- **当前实现与审核**：应用V3原V2两问题闭合，但独立新增2P2（第二动作provisional archive遗漏却发双写receipt、seek cancel后late play）。原作者两次修正已用完，Lead接回V4，仅改page/lifecycle；当前provisional显式requireArchive双写，每pause/play紧前fresh gate。53tests/analyze/diff通过，原两反例重提取2PASS、真实FS健康/first partial/second partial3PASS、protected17SHA匹配；V4已冻结/归档，REPORTb22bad8b/manifestf0c10561，Lead停止释放Flutter，正式V4独立复验正在进行。build draft已更新ownedSHA但approved=false，无新APK/ADB。

### 2026-10-04 V5 independent PASS, lifecycle R2 built/installed

- V5独立完整report已读，SHA33bb803f35a48b9bf1cf6ed26158dc229975a173e5501b789956ebd26e1aaf7d；56tests＋实际page5tests/analyze/SHA前后通过，Flutter释放。Lead批准新R2构建，approvedV5清单绑定22source，固定JAR/lib。
- Build exit0/install Success，installed-base.apk全回读 SHA2523d969f9dc3521add9225d308aac4d17bf7a6720c003d762bc3868bdc7ae84匹配候选，lib7cc6f4ac一致。label lg-p5-session-lifecycle-r2-20261004，900s。尚未启动新版。
- 设备P5/SDR完整回读/hash进程session63415确认仍运行，watchdog每源120s，未超时重启；完成后保留lifecycle-r2-device-sources.json，再coldlaunch新anchor。无本轮人工/动作验收。

### 2026-10-04 R2 actual startup/pause and visible/cleanup failures

- P5/SDR设备完整回读SHA均固定一致；wake Awake/ON/keyguard=false。coldlaunch fresh1791106109081252-10930378/900s锚点成功，初始实际ready/rows2/debtfalse启用8动作，修正startup实际闭合。Pause10Resume唯一tap→external end-certified证书身份/hash/原hostdeadline通过，requesttap-1/payload587724e6，report21；只app action证据。
- 人工反馈“只看到横向细长一条画面”；实际screencap thin-strip.png显示16:9视频大部被顶部diagnostic/lifecycle控件黑色面板覆盖，底部仅细条可见。latest row仍qcomDV/native/timed/g1同Surface、time70/drop0；不替代可见验收。布局失败，未继续其余case。
- 执行页内close-and-exit requesttap-2，observer error：Actual Session restoration did not match baseline（capture），其他recorder/session/player/terminationReport错误null；系统focus Launcher。清理未通过，保留原报告，不把返回桌面当恢复证明。已sleep。
- 全部启动/动作/截图/报告/素材身份归档。下一步先隔离诊断面板与video区域布局，另查真实restoration基线差异；尚不称8case完成。

### 2026-10-04 R2 layout correction and cleanup delta isolated

- Root已从close原事件session-disposal-proof取出baseline/post：唯一option差异hwdec no→mediacodec，source/path/playlist、native_dv option/renderMode/codec/vo均匹配，epoch稳定。恢复检查未放宽；需查是否Controller async初始化先后造成基线漂移。
- Root仅page UI将Session diagnostic Stack overlay改为SafeArea Column，上video flex3/下可滚动panel flex2，保持同HdrVideo/16:9/controls context，消除互遮；page analyze无问题/diff通过，尚无新APK/真实布局验收。
- 只读team_scout lg_cleanup_baseline定位prepare baseline与controller初始化/owner快照顺序，禁止源修改/Flutter/ADB；Root独占page，等待50s未完成。V5已审源码与R2证据保留，当前page布局WIP未冻结，不能复用旧批准哈希构建。

### 2026-10-04 hwdec ownership ordering root cause and bounded implementation

- Scout只读确认确定顺序：diagnostic.prepare在75ms捕获idle hwdec=no；Session outputSlot初始空，prepareOutput ensure创建AndroidController，其init写route.hwdec=mediacodec；backend configure才_setOwned hwdec，首次抓到mediacodec，dispose因此恢复错原值。不是先等controller再采baseline的理由，不重置baseline以掩盖差异。
- Root已读backend _setOwned/prepareOutput/configure，批准窄方案prepareOutput.ensure前_setOwned(hwdec,route.hwdec)，保持configure ready后回读及nativeDV pair/锁/默认maturity/严格恢复门。team_worker lg_hwdec_restore_fix独占backend＋新ownership test＋Flutter，Root page布局停写/不跑Flutter；要求改前生产复现、真实backend+slot transport替身、normal/fail/repeated/invalidbaseline和相关suite。无新build/ADB，待freeze/独立审核。

### 2026-10-04 separate layout freeze and backend test boundary

- Root页内上下分区布局已单独冻结lg-session-layout-v1（page源/SHA/v5diff/analyze），不修改worker backend/test；尚无新device布局验收。
- Worker对Player/VideoController concrete接口替身有疑问，Root重申任务已批准implements/noSuchMethod transport替身；真backend+真slot保留，fake仅属性/stream/lock/controller readiness，不调用native构造器、不增加产品seam、不旁路reset。共同hwdec顺序用无pairroute隔离，native owner/policy既有suite另验证。源/测试实施继续，无Flutter并发。

### 2026-10-04 output ownership test harness and runtime evidence

- Root只读initial baseline-fail末18行是替身接口编译失败；worker后续修接口后不慎覆盖原全日志为runtime failure，已确认原全编译日志丢失。Root保存明确非全原始的tool观察摘录，要求REPORT说明，禁止再覆盖。不能称编译失败证明产品缺陷。
- Worker报告修前runtime5失败，实际reset后hwdec仍mediacodec而预期no，空/读失败未阻止controllercreate；另存当前runtimefail副本。修后5/5通过，相关suite运行中。Root未并发Flutter/未触碰owned文件。

### 2026-10-04 旧 Current State consolidation snapshot（R4 独立审核中）

### 历史 Current State 快照

- **新采证/单scroll候选已冻结并交审**：SDR证据 worker19 tests/owned analyze/format通过，diag7801b2c/testb68e1b5/REPORT882088db/manifest1f2281f1，已独立回读并对R3已审基线冻结diff。Root page28de4577（移除内scroll/maxHeight）格式/定向analyze/diffcheck通过并停止。default_ps_api_review 新组合V1已running，重点原predicate语义不变与真实8按钮横竖屏滚动/tap可达性，前审stub不够的限制已明确。R4 draft approved=false、23-source逐个匹配（仅3项本轮owned变化，其他20项R3一致）；尚未构建/安装。Flutter已交reviewer，Root无live测试/ADB，LG最后熄屏。

- **R3 输出动作补测与下一候选**：独立健康run1791108168949954-774541706，RestoreSurface tap1完整end-certified（deadline内收到），后close tap2 end-certified/closed/debtfalse、严格Session恢复报告；原APK/source身份沿用R3实测，不冒充新源码。FullScreenRoundTrip/RecreateSession因控制面板嵌套scroll导致底部按钮无法滚到而未执行（两份XML/手势证据归档）。Root已移除 lifecycle controls 内层scroll/maxHeight，保留下方外层唯一scroll；冻结前snapshot在lg-session-layout-v2，格式/analyze/实际8按钮可达性验证待worker释放Flutter后做。worker lg_hwdec_restore_fix 正在实现仅SDR predicate拒绝证据增强，未改变任何接受条件；全部ADB运行结束并熄屏，无live Root exec。下一步两改动freeze/独立审核/新包采真实失败mask再决定SDR契约修正，不能用当前推测放宽条件。

- **R3 本轮收尾结果**：run1791107639256966-185208592 的前3动作证书成功，P5SDRP5 tap4失败：SDR routeApplied报告sdrDirect/h264/mediacodec-copy，但SDR segment 0row因复合AVC/idle-option谓词拒绝，后续60s admission超时。实际失败字段未持久化、logcat0bytes，不能确认真实AVC wrapper配置或唯一失败分支。清理债务禁用全部按钮（close-tap零tap locator拒绝）；解锁后Back返回Launcher但cleanup pending，不算strict close。保留失败现场后新健康run1791108040023988-1017702864单独验证close-and-exit tap1 end-certified：closed/debtfalse、Session baseline全部恢复verifiedtrue（hwdec no）、player-termination completed、Launcher；Surface release独立ACK仍unverified。末尾恢复timeout30000/熄屏。worker新任务仅SDR拒绝证据增强（diagnostic+test），保留predicate/guards，不直接改验收基线；Flutter已交worker。R3 APK09a4728b，固定源/installed全SHA一致；未提交推送。

- **R3 正在实机验收**：独立合并 V1 host PASS（REVIEW453ed677、manifestc06bde8a；103 回归+6 strengthened+2 布局通过、Flutter释放）。23-source匹配后已构建安装 R3 APK09a4728b / lib7cc6f4ac，installed APK/lib完整回读一致；新run1791107639256966-185208592绑定原900秒deadline，startup采样正常。截图完整视频与下方诊断面板不重叠；用户回复“都正常”，确认本次完整画面、颜色、亮度和流畅性。固定P5/SDR全设备字节hash匹配。Pause10Resume、Seek90Then30、Reopen40Then10已获deadline内完整end-certified；P5SDRP5执行中，其余动作与严格退出恢复待采证。材料 native-dv-session-lifecycle-release-r3；不迁移为HDR10/SDR映射/全生命周期验收。

- **最新进展（R2 后修复）**：R2 实际 startup 与 Pause10Resume 证书采证成功，但用户只见横向细条；截图确认诊断面板遮挡视频。close-and-exit 返回 Launcher，但严格恢复失败：hwdec 基线 no、退出后 mediacodec。已定位为 controller 初始化先写 hwdec、backend 随后才登记原值。Root 已冻结上下分区布局修复；worker 已冻结 controller 创建前登记 hwdec 的修复及 5 项 backend/slot 集成测试，核心回归 103 项通过，定向 analyze/format/diff 通过。全包 analyze 有 19 项诊断。独立合并审核 default_ps_api_review 当前 running；R3 尚未构建安装，两项修复均待实机验收。原始首次测试编译日志未保留的限制已记入结果单。材料 lg-hwdec-output-ownership-v1 与 lg-session-layout-v1；未提交推送。

- **目标与授权**：LG-H870DS API24 的解码/显示能力、hdr_lab 移植、SDR/HDR10/P8.4/P5/native DV 明确路由、Release 性能与完整生命周期仍 in_progress。安装与设备实验已授权；未提交/推送。不覆盖其他 Darwin 或共享 renderer 修改。
- **设备**：LGH870DS42e27764 / Android7 API24 / Adreno530 / arm64；系统声明 HDR10/DV，无 HLG。能力声明不等于性能或面板验收。Root本次重新读取 power=Asleep/OFF；timeout 已恢复30000。没有本轮新播放。lifecycle-prebuild-device-state再次只读确认唯一LG adb online、package存在、Asleep/OFF，未重新回读APK字节。
- **最新实际 Session 运行**：Session Release R1 APK `07d383b0` / lib `7cc6f4ac` / JAR `23036e0b`，run `1791074230838199-809604165`；真实 consumerValidated 与 native RouteApplied 同 generation1，qcom DV/timed。全EOS263.041667秒、53rows、VO/decoder掉帧计数0、error null、DropBox不变；installed APK/lib/原P5完整回读绑定通过。材料 `artifacts/lg-hdr-20261004/native-dv-session-release-r1`。计数与结构不代替人眼验收。
- **当前验收缺口**：当前Session R1人工颜色/亮度/流畅性尚未回复；系统Back返回Launcher且Dolbyoff，但报告 `cleanup=pending`，不能称 Session owned选项恢复或Surface释放通过。旧Release SDR映射人工“颜色正常，但卡顿”仍为性能失败；独立Java P5/HDR10的正常观感不迁移为demo验收，HDR10亮度仍缺。
- **当前实现与审核**：V4独立PASS后lifecycle Release R1 APKd6a56511已构建安装/回读身份，但actual coldlaunch初始open被strict action gate拒绝（startup缺busy/current scope），row0/debt，无播放验收。Lead V5新增严格一次性startup scope并接真实page initialOpen，56tests/analyze5/diff通过、protected17SHA匹配，已冻结REPORT5725d14d/manifest72fbfd16。独立V5首轮因usage limit错误终止，无报告/产物；Root live usage显示ordinary allowed后只重试一次，agent已running且50s等待超时。V5未批准构建，设备失败实验已force-stop/sleep；目标继续。

- **生命周期目标与契约**：默认关闭 `MEDIA_KIT_ANDROID_NATIVE_DV_SESSION_LIFECYCLE_ACTIONS`；总预算1..900秒、全run≤300rows、segments≤24/actionEvents≤128/proof及Applied各≤48。8动作：close-and-exit、Pause10Resume、Seek90Then30、Reopen40Then10、P5SDRP5、RestoreSurface、FullscreenRoundTrip、RecreateSession。固定P5与已核验SDR控制源；真实API、串行动作、独立段身份，不伪造codec/capability，不引入第二owner。清理债务阻止复用/重建。
- **已审基线**：single-session fixture V2独立V1 PASS（11 tests及实际EOS链1 test）、Session observer160 tests与独立审核通过；producer v3、Session policy v2、native默认MP4 PS-only修复及owner/backend保护此前已独立通过。旧direct Release R1/R2全EOS与恢复证据仅代表raw direct，不替代真实Session生命周期。精确冻结SHA、失败反例与原始日志保留在下方历史和artifact目录。
- **最新外部契约**：Root observer v3证书/coldlaunch原deadline接线草案31hosttests通过，V3独立3P2已Root correction1修正，V4独立PASS：原4反例/32tests/failed-anchor入口/真实Dart中文互验均通过；报告与输入SHA归档。完整certificate须在coldlaunch before-ADB host monotonic+原预算内收到，禁止tap前重新预算；旧end拒绝。新工具未用于设备。
- **Root外部工具**：UI trigger-v2强制package/serial/唯一enabled Semantics，仅tap一次，17host测试Root复跑PASS；action observer绑定run/label/唯一新request，现17host测试PASS（包括晚到拒绝、run变化、ackError及closedBeforeAction/deadlineRejected/reportError终态；end-pending不算成功），phase-contract-v5已归档（含完整main轮询pending→三失败终态，不误报成功），待writer最终契约复核；phase-contract-v5及summary草案外部工具独立只读V1已交reviewer，未占Flutter，不重tap/重启、不推断画面。collector schema2草案8mode+9bounded-shape测试通过，独立回读P5/SDR/APK/lib；build guard要求对应mode/新journal与test SHA及精确两个define，错误清单已反向拒绝。Root已准备22-source lifecycle构建draft（approved=false），受保护核心SHA均与已审基线匹配（attempt1期间Root再次核验17项无漂移，receipt correction-attempt1-protected-check.json），draft状态已同步正式V1 REQUEST CHANGES且仍禁止构建；本轮host预检JDK17.0.20.1/28Gi可用/JAR23036e0b与lib7cc6f4ac固定SHA匹配（lifecycle-prebuild-host-state），draft check-only拒绝；最终freeze后需刷新owned SHA并独立V1。新增schema2逐段summary草案经独立V1发现1P2（同段known计数跨unknown下降漏报），Root attempt1已修正为段内known序列比较，7host tests＋原独立反例通过；summary-v2冻结后独立V1 PASS（原反例未改复跑0、7tests0、SHA匹配），原报告/失败日志保留；原草案5host tests通过，缺失counter保持unknown、仅段内报告reset，不给画面/性能结论；材料session-lifecycle-summary-draft，冻结v2契约已Lead只读对齐collector/observer；summary-v3额外透传phase/error/exitAcknowledgement/endScope，Lead V0＋8tests通过，原counter逻辑不变。工具尚未用于schema2设备实验，最终仍需冻结契约对齐。材料各在 `artifacts/lg-hdr-20261004/`。
- **后续 HDR10**：已完成boolean→timed→boolean隔离设计 `hdr10-demo-timing-plan`；固定PQ `/data/local/tmp/media-kit-lg-pq-4k30.mp4` 主机与设备全76438009bytes/SHA `3068be37`匹配（receipt `hdr10-timing-device-preflight`），2:1几何。普通demo成功configure-input全格式尚缺；不注入Java静态HDR元数据、不扩大DV owner、不改默认boolean。尚未实现/执行新HDR10对照。
- **后续 SDR 性能**：Root重新摘录历史Debug copy-matrix，P5实际gpu-next/mediacodec-copy在0.58→4秒VO计数5→27，decoder0，nv12/12bpp；不混入早期软件解码或Release人工观察。准备同APK/源/4K/几何/温度的baseline→单项scaler→baseline及copy/render隔离，尚未新实验或定根因，材料sdr-performance-preparation。
- **后续负向实验**：设计 `native-dv-session-negative-device-plan` 已回读：N1真实Surface未挂载导致既有10s超时→同代exclude/rollback/fallback优先；N4 accepted后foreign source→dispose拒stop/restore与debt单列。现无对应已实施入口；healthy切源/off/OpenSuperseded不算故障回退。
- **接下来**：完成lifecycle真实采样与8动作/异步tests→freeze/source SHA→独立V1→匹配mode构建/安装→逐case设备采证与人工验收。随后HDR10对照、SDR/P8.4性能及真实失败回退；现代Vulkan设备回归仍缺。完整目标未完成，不能升默认nativeDV成熟度或标任务complete。


### 2026-10-04 R5 stale fullscreen layer root-cause evidence

R5 SF两非零visibleRegion且alpha ff的Surface层分别为全屏大层与1440×810中心覆盖层；新dump带host capture时间边界，截图直接证明覆盖，不能将通用Surface名绑定具体viewId。Scout独立源码核对：默认fullscreen.dart43–109保留旧Video并新增Video；Factory245–319独立保留各Java Surface。real.dart1245–1269严格停旧producer并清bound tuple，但live旧owner cancelRelease；1009–1015 drain跳过live，因此旧JNI引用保留供fallback，未控制presentation。Java PlatformVideoView ctor API<=25 setZOrderMediaOverlay(true)；377–409 releaseSurface仅失败代次INVISIBLE。最可能根因为保留的旧Surface最后buffer仍可见。新只读Specialist android_surface_visibility_design核对API24可用显示控制与恢复方案中；不得假定setAlpha可影响该版本独立Surface，也不得无证据直接INVISIBLE破坏Surface/WID回退。产品尚未改；目标保持默认fullscreen transport与strict owner/producer生命周期。
