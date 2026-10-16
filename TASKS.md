# TASKS.md

任务事实源：这里只保留当前状态、验收门槛和下一步。清理前的完整任务台账快照：`archives/experiments/tasks-ledger-snapshot-20260927.md`、`archives/experiments/tasks-ledger-snapshot-20261002.md`、`archives/experiments/tasks-ledger-snapshot-20261010.md`（2026-10-10 精简前全文快照）；按各项 `context` 查看持续更新的依据。

**路径映射（2026-10-05 起）**：`archives/experiments/` 已整体迁移至独立仓库 **`~/src/media-kit-experiments`**（实验记录/证据/交接/索引全量归档）。本文件及 conversations 中所有 `archives/experiments/` 前缀路径均映射到该库根目录。**主库历史已剥离该路径（2026-10-06，main 51ef66cc→ee28accd，树零变化）**：剥离前提交历史不再在主库，查备份仓 `Goodwu/media-kit-history-archive`（分支 `pre-strip-20261006`）；旧哈希换算用 `~/src/media-kit-build/history-strip-20261006/commit-map.json`。

## MK-ROUTING-20261011（CORE继任）
- 2026-10-16 措辞修正(V2 三审 R3):`HDR review:` 诊断行的快照字段声明从"完整 A/B 快照"改为"截断摘要"(完整设备序列以验证轮 raw logcat 文件为证,该行不作恢复源);并修正注释中 `_mediamediacodec` 拼写。
- 2026-10-16 V2 三审 FAIL 两缺陷修正（单向附着+结算模式校验）：①in-pair 附着发布只允许单向（首半=已登记标签、次半=其 `_mediacodec` 形式）；A 半已附着而 B 半回退=可观测逆向，拒绝且不被后续稳定洗白；②跨轮附着结算的 hwdec 模式取"本轮实际发布值或本轮值"并要求 `startsWith('mediacodec')`——空→surfacetexture 发布不再能结算附着。精确形状测试 5 项新增（同轮空→异值、登记配置空→异配置、完整 A 消失 B、反向附着、非 MediaCodec 发布），并以 8f00ec76 worktree 探针取得旧红（两缺陷形状在其上完成成功）新绿（收窄契约拒绝）执行证据。review 40+diagnostics 10、video 全量 **917/917**、analyze 0。勘误：此前 8f00ec76 提交漏含本两处修复（工作树有而提交无，git stash 时序事故），设备验证实际跑在含修复工作树上；本提交补齐。
- 2026-10-16 用户样本扩充（b8da287d 版 APK d167e153…，marble）：BV1vY4y1N7TY **PASS**（区域差 0.6120，软解路径稳定通过）；BV1uZ4y1U7h8 与 BV1WPNh6zEcx **确定性失败**（4/4 轮，含重试）：`outcome=endpoint-changed changedKey=current-tracks/video/decoder changedA=h264_mediacodec changedB=h264`——mpv 硬解在这两片流上反复失败回退软解，decoder 标签在 1-2 秒内持续翻转，按 V2 契约"已登记后回退必须拒绝"门在 1.4-2.2s 显式失败（非超时）。此为解码稳定性问题（mpv 层），非门语义缺陷；用户重试 UX（失败→重试按钮）与 mpv 硬解回退策略属后续裁决项。LG 同样本未测（LG 在线时间窗）。证据 /tmp/w5-verify-20261015/bv-marble-*。
- 2026-10-16 修正版设备复验通过（库 8f00ec76，APK f6e7d78e…）：marble 冷开区域差 **0.5610**（review success iter=14，结算 h264_mediacodec+mediacodec-copy+c2.qti.avc.decoder）、LG **0.6099**（success iter=7，OMX.qcom.video.decoder.avc 硬解），零 ANR/FATAL。R1/R2 收窄后两真机发布路径仍收敛成功。证据 /tmp/w5-verify-20261015/e2e-marble-final3、e2e-lg-final4。已提交 V2 第三次复审（8f00ec76 差异+红绿矩阵）。
- 2026-10-16 V2 二次复审 FAIL(R1 空侧"首发布"可覆盖已登记基线/R2 发布轮的 A 半可直接当 facts 返回/R3 a/b 快照被 field 层 200 字符二次截断)后修正：①首发布绑定"该字段无已登记值+方向空→值"；已登记值后出现空半=消失观测，fail-closed，不得重授权/换基线；②in-pair 附着标签发布=已登记 X、双半 X/X_mediamediacodec、同 hwdec 模式+同配置；③发布轮一律 return null(登记结算侧后强制重采样)，不得当轮返回 facts；④附着结算=守卫内独立受限迁移(值=已登记+`_mediacodec` 后缀、登记配置未变、mediacodec* 模式)。新增 3 红绿测试(标签 X→空→异标签拒/hwdec X→空→异模式拒/发布轮重采样断言 elapsed≥50ms)。review 35+diagnostics 10、video 全量 **912/912**、analyze 0。同时修正 `_mediamediacodec` 拼写笔误与"explicit adjudication accepted"措辞(改为 separate adjudication 待裁决)。LG 用户手测两片 DV 失败取证：同根=普通路径无 owner token,yuvWindowArmUnavailable(W1 未实施),fail-closed 设计内；marble 用户手测 DV 出错同因待取证。
- 2026-10-16 跨轮附着结算补全(46f21a0b 后真机复验发现)：readiness 版 APK 上 marble 再捕获新形状——早期轮已把未附着标签 `h264` 登记为基线(hwdec 未发布+pixelformat 空)，随后轮 A/B 相等观察到 `h264_mediacodec`+hwdec 发布 `mediacodec-copy`+同登记组件配置——附着发布跨轮发生，守卫按漂移拒绝。补全：守卫的 decoder 键在精确条件(值=已登记+`_mediamediacodec` 后缀、登记 MediaCodec 配置一致、hwdec 为 mediacodec* 模式或本轮 hwdec 发布)下允许附着结算超替基线；其余漂移不变仍拒。新增跨轮结算契约测试(真实时序：未附着期无帧格式)。review 32/32、video 全量 **909/909**、analyze 0。
- 2026-10-16 V2 复审 FAIL(R1 整轮跳过/R2 证据截断/R3 诊断安全)后按修改要求重写并补齐最低测试清单：①循环重排=identityAfter 前置于一切发布处理(R1.1)、双半 config 合法性+nativeDV 检查前移(R1.2)、发布契约白名单化(R1.3:仅"单侧空的首发布"与"同 hwdec 模式+同 MediaCodec 配置下的 `X`→`X_mediamediacodec` 标签附着"两种，其余失配仍拒)；②observed 守卫每轮登记，受支持发布以结算侧超替基线(绑定事件)，其余漂移仍拒；③诊断安全(R3)：三态 identityOk(unchecked/ok/failed)、elapsed/loaded 相对起点、快照轮作用域、值转义+200 字符截断+整行 3600 上限、sink 抛错不改变结果、未知错误只记 runtimeType。新增测试：T1 组件冲突不洗白/T2 malformed 先于重试/T3 已登记 hwdec 基线漂移仍拒/T4 发布窗口内源漂移即拒/T5 同名异配置拒绝/T6 marble 两形状重放(hwdec 空发布+标签附着)成功/T7 诊断安全(URL 隐私/转义限长单行/sink 抛错/非零时钟/半轮不混快照)。review+diagnostics 41/41、video 全量 **908/908**、analyze 0。已知残余(记录待单独裁决)：组件名≠实例证明，同名同配置真换实例不可由现属性区分；设备端 logcat 往返完整性待真机轮验证。
- 2026-10-16 Q1 证据到手+readiness 协议实施：诊断版 APK 上 marble 真实打开捕获决定性证据——`HDR review: outcome=endpoint-changed iter=9 elapsedMs=1822 loadedMs=664 changedKey=current-tracks/video/decoder changedA=h264 changedB=h264_mediacodec`,两侧 hwdec-current=mediacodec-copy 相同、android-mediacodec-info 同一组件(c2.qti.avc.decoder)、A 侧 pixelformat 空——即 hwdec 附着中轨道标签未稳定,非解码器变化。据此实施窄 readiness 规则(基线感知:仅当无已登记 decoder 基线+hw 模式激活+标签无 `_mediacodec` 后缀+pixelformat 空→本轮视为未就绪重试;其余契约不变:A/B 差异仍拒、observed 基线守卫先于 readiness 吞没、完整但冲突样本仍由 plan 验证拒绝、预算共享 fail-closed)。新增 3 契约测试(marble 形状完成/永不稳定超时/基线后无后缀漂移仍拒)。review+diagnostics 31/31、video 全量 **898/898**、analyze 0。**门语义变化已触 V2 复审条件:装机验证前提交 V2 复审。**
- 2026-10-16 Q1 取证第一步落地（按 V2 裁决 (d) 的"库内有界受控诊断"方向）：`hdr_output_diagnostics.dart` 新增 `HDR review:` 层（单行、每次复核 gather 出口一条：outcome/iter/elapsedMs/loadedMs/phase/identityOk/changedKey/changedA/changedB + 完整 A/B 快照；隐私契约=不记录源路径值，完整性仅记布尔）；`hdr_decoder_review.dart` 的 gatherDecoderReviewFacts 接相位跟踪与发射（try/catch 包装，零语义变化：读序/重试/准入/A-B 拒绝全部不变）。新增 test/hdr_decoder_review_diagnostics_test.dart 5 项（mismatch 快照/timeout 相位/identityOk/success 快照/默认关闭零输出+路径值不出现在日志）。video 全量 **895/895**、analyze 0。既有 23 项 decoder review 契约测试全绿=门语义未动。App 侧仅在 main_native.dart 加一行 `HdrOutputDiagnostics.enabled = true`（诊断消费，走公开导出面）。


- 2026-10-15 本地agent接续（交接锚点库 d5f30c7e / App 9b55f194b）：P0 三项 hdr_yuv_presentation_contract_test 失败已本地复现（与 CI run38731073045 一致：2×HdrOutputPreparationFailure yuvWindowArmUnavailable + 1×HdrOutputLeaseConflict 未初始化 ServicesBinding）并修复。根因=784df146 将默认 arm 管理器构造移入 AndroidHdrBackend 后，旧 `_exercise` 夹具（无注入、无声明 yuvWindow 通道、无 owner token）从"只测输出写入"越过到真实资源/平台边界。修法仅动测试夹具：经既有 `yuvWindowArm:` 构造 seam 注入同一真实 HdrYuvWindowArm + arm-integration 组既有 FakeArmAtoms 通道/原子替身，`_issuedPlan` 声明 accepted quad 蕴含的 YUV 窗口 PQ 通道（同 yuvPlan 形状）；准入/owner/lease 检查全部保持真实，生产默认资源管理器未关闭，零删用例/弱化/skip/binding 掩盖，断言零修改。本地验证：video analyze 0 + 890/890（CI 基线 884+3skip+3fail）、lab analyze 0 + 292/292、managed_output 4 OK、routing 工具 6+17+27 OK；修前/修后证据 /tmp/mk-p0-fix-evidence-20261015/。实施记录已追加 docs/plans/managed-yuv-implementation-20261015.md。仍开放：W1 通用受管 provider/Surface 协议（普通无 token YUV 冷开）、W3 App 八项 pin 更新到本提交、W4 native ELF 拒绝、W5 设备矩阵。

- 用户最新优先级：DEVICE源码归并；CI跟进、新构建与其它开发暂停。本次两仓提交带`[skip ci]`；公共主PR不向正式base合并、不发布。
- App PR3@9895e7dc的9代码/测试文件已按源字节归入，含DV003/DV005/DV006和debug applicationId变化；状态CODE_INTEGRATED_KNOWN_ISSUES_OPEN。HTTP/cache/track/localURL与亮度reset/事件/权限/lifecycle问题继续开放。
- 库PR6@9a2c5768归入来源历史并完整归档原文；公共gather及跨轮拒绝断言保留，新增2兼容plan负例。FIRST-complete-only行为未启用，实际decoder序列和两个用户决策继续开放。
- PR5@dc417870的两脚本原文归档为`.sh.txt`，继续排除于可执行配方；公共matrix/已有审查文档和三provenance banner不覆盖。
- native同名公共routing已指向1095a43a，包含3笔DEVICE原提交；原DEVICE/feature/main与原PR1不变。DV001/PR5配方整改、fresh native、最终JAR/APK、设备HDR与持续性能验收必需未完，接受ledger空、批准native0。
- DV006新增读取DEVICE comment6128050177的LYA用户手势观察；该回报不关闭NaN reset/事件/权限/Activity handlers问题。原review结论继续有效，旧“暂不归并”的排期由本次用户指令更新。
- 本次只核三方归并、精确source/blob/SHA、保留门与提交回读；没有新Flutter/Kotlin/native运行结论。此前App3884+库4d1d受验结果与历史a3b+e269结果保留原标签；general38275707106的最后已读观察停在16:49:33 UTC，本阶段不续查。
- CORE Web/订阅/Flutter pin与既有query/DASH/F01/R01/config保留。experimental默认false，true主验并测false；LG YUV8/FULL/range1/精确设备/ownerACKlease保持，10-bit/lease融合延期。
- 完整处置与来源索引：`docs/plans/core-device-integration-20261012.json`（库中央含独立报告）；唯一`archives/conversations/media-kit-routing-20261011.md`。用户已授权确认归并后删除相应来源分支；逐ref核HEAD/祖先/处置后清理，结果回读登记中央PR4。保留全部公共routing及未合并的native原PR1分支。后续同一DEVICE从公共HEAD认领App/DV004修订，native仍原PR1；CI与其它代码维持暂停。
- 2026-10-13 安卓构建+五机回归（routing@5834ce5b）：测试链四 APK（p5/p84/hdr10/sdr，lib 槽位 5f8fc04c 与 10-10 基线一致）；顺带修复 `tool/build-android-test.sh` flutter 步骤 melos 根必失败缺陷（53ede203 引入，定稿版此前从未端到端跑通）。结果：LYA 3/3 绿（与 10-10 基线逐格一致）；marble p5/p84 绿+hdr10 首跑触发**新解码履行复核门竞态**（HdrDecoderReviewFailure "Observed decoder changed"，同路由复跑 marble5 完整通过——间歇 flake 待修；2026-10-13 修复尝试已回退（见下条），修复策略属 DV004 两项开放决定）；LG 3/3 对照 LG 基线通过（P5 nativeDV verified、API24 加载正常；p84/hdr10 色彩留 30s 人工目视旗标）；jason 2/2 对照 09-30 基线通过；ugg 用户解锁后补跑 ugg5-sdr 通过（sdrDirect/verified、零 fatal、EOS/dispose 闭合）——**五机 5/5 全数通过，目标闭环**。②post-EOS BACK 不 dispose 本轮复现于 LG(API24)/jason(API35)——"HyperOS API35"归因不成立，修正为设备相关待查（复现 marble/jason/LG，LYA 通过）。tap 协议修正：横屏输入空间 tap=(逻辑短边/2,同)，旋转设置轮前 1/1 轮后还原。context：`archives/conversations/regression-two-device-20261013.md`；证据 `~/src/media-kit-build/evidence/regression-two-device-20261013/`。
- 2026-10-13 本分支代码变更（本合并带入，未推送）：① 平台线程 ANR 修复——主 isolate 事件泵去 kDebugMode、新增 mpv API isolate（`media_kit/lib/src/player/native/core/mpv_api_isolate.dart`）承接同步属性/hook 调用、set_property async 超时 5s→30s，analyze 零 finding，设备复验待跑；② 解码履行复核门竞态修复尝试已回退——未稳定样本改重试与既有契约测试（A/B 混合快照拒绝已稳定 `video-params/*` 差异）冲突，且 flake 报错 "Observed decoder changed" 实来自跨轮 identity 基线而非 A/B 对比；源码已还原公共原版，`hdr_decoder_review_test` 23 项全绿。基线时序策略与 DEVICE `0fb163c6`（first-complete-only，终审未批准）同类，属 DV004 两项开放决定，flake 仍待修待裁决。详见归档 2026-10-13 段。
- 2026-10-13 远端 HDR 路由检查点本地验证收绿（routing@e40cef8f）：ff 合入远端 8 提交（六源码测试 + 两文档；dirty 归档已快照保留）。该头首验：analyze 双包零 finding、聚焦 63/63 过，但全量 39+1 项失败——均为仍编码已废"隐式 SDR 兜底"契约的未迁移旧用例（CI 38417189657 两包 test job failure 同证）。已全部迁移至 v4 第 1 节不变量（0 ESCALATED、无删用例/弱化断言/新开关），删除 `hdr_video_session.dart` review 路径 `hdrAttempts>=2→preference.off` 死分支与过时注释，新增空候选目录阻断占位专测；终态 media_kit_video 788/788 + media_kit_hdr_lab 298/298 全绿、analyze 零 finding。本地提交未推送（push 逐次请示），推送后 CI 须在实际新头取 success 方可记最终验收。v4 第 4—7 节剩余（C1—C4 stage 模型、去 experimental 开关与成熟度准入、4.2 错误模型、4.3 候选表、4.4 快照重试、4.5 元数据所有权、HDR10+/Vivid routeNotImplemented 入口、C4 仅 HLG→PQ、PiliPlusX 配置/报告共用、验收矩阵）与 native B1—B4、设备验收均**未实施**。context：归档"2026-10-13 本地验证与契约迁移收绿"段。
- 2026-10-14 实机回归（routing@ab1c7ca9，最新源码三 APK）：**DV P5/P8.4/HDR10 三样片实机解码测试全部完成**——LYA 3/3 与基线逐格一致（p5 reshape→PQ 全片 EOS、p84/hdr10 baseLayerDirect + SF 实锤 HLG/PQ 层）；LG p5 nativeDV 全片 EOS + hdr10 baseLayerDirect 254s 零丢帧；jason p5 toneMapSdr verified（display=确定 SDR-only，**新契约豁免分支实测有效**）。**LG P8.4 硬失败=契约预期**：同一 dataSpaceApplyFailed 上轮实为降级 toneMapSdr 播放（回读 lgh4-p84 日志 ACTUAL=output:sdr 实锤），兜底废除后 LG P8.4 无可达 HDR 输出路径——开放项归 v4 A 包候选表，不恢复兜底。marble（dede0cd2）用户报在线但本机 adb 全程不可见（检测留痕），marble6 三轮待设备可见后补。已知 flake 未复现；设备全部还原核验。native 层与基线逐字节一致（lib 槽位 5f8fc04c）。context：`archives/conversations/regression-latest-20261014.md`；证据 `~/src/media-kit-build/evidence/regression-latest-20261014/`。
- 2026-10-14 v7.3 第一批本地收绿（routing@d3a4ab23）：远端十提交（`fa5cb8a2..d5a270a7`：C4 仅 HLG→PQ、HDR10+/Vivid C1 身份+C2 routeNotImplemented、stage/candidateId 与 prefer 仅同阶段重排、DV 默认序 C2 在 C3 前、成熟度门删除、legacy experimental 兼容）落地后本地全量 31 项旧断言失败（compact 截断初计 18、expanded 复核 31），已全部迁移至已裁决不变量——0 ESCALATED、无删用例（+2 新增：hdr10Plus 固定目录错误保留、C2 错误后 C3 续走 verified）、无弱化/开关；P8.2 按 §10.3.3 双态语义迁移且规格级用例保护保留；§10.3.4 重试时序四点核验覆盖。终态 media_kit_video 808/808 + media_kit_hdr_lab 298/298 全绿、analyze 零 finding。本地提交未推送（push 逐次请示）。下一步 §10.3.5：experimental 字段整体删除（库/Lab/App）+ PiliPlusX dirty 迁移。context：方案 §10 本地验证回执。
- 2026-10-14 晚 v7.3 tip 全在线设备回归（routing@01fd8e39，regression-v73-20261014）：**4/4 台在线设备完成；三样片解码测试达标——P5 于 LYA/LG/jason 三台通过（reshape→PQ EOS、nativeDV EOS、SDR-only toneMapSdr EOS），P8.4 于 LYA 通过且路由变化实锤（stage 序 C2 reshape→PQ 取代 C3 HLG 直出，SF 实锤 PQ 层；LG 为契约允许的显式阻断：C2→PQ dataspace 落盘 dataSpaceApplyFailed 无 SDR 兜底，缺口维持开放），HDR10 于 LYA/LG 两台通过**。零 fatal/crash、flake 未复现；ugg 三样片不可行有确定性能力证据（HEVC 硬解 1080 上限/软解 4.19M 像素上限/SDR-only 显示）；marble 仍不在 adb 列表。设备全部逐字节还原。构建源未推送（push 逐次请示）。context：`archives/conversations/regression-latest-20261014.md` v7.3 轮；证据 `~/src/media-kit-build/evidence/regression-v73-20261014/`。
- 2026-10-14 推送与最终 CI 收口：`d3a4ab23..7a53bc78` 三提交已推送（远端未漂移）；最终源头 `7a53bc78` 的 hosted **Routing source checks = success**（38439658417 批次；Darwin viewport/query checks 同绿，平台构建矩阵随后跑非验收门）——v7.3 第一批源码门全绿闭环。PiliPlusX 依赖 pin 已更新至 7a53bc78（本地 pubspec.yaml 改动保持未提交，与其 WIP 一并由用户提交；analyze 零 finding、route_options/evidence 测试 36/36）。
- 2026-10-14 §11 元数据所有权+独立验收矩阵本地收绿（routing@ba97ab2c）：远端八提交（HdrMetadataHandling 四态声明模型 + requestedMetadataHandling/observed 语义 + 5 项契约测试 + Vivid 重分类重建修正 + docs/validation/hdr-route-matrix-v7.3.json 52 格矩阵与 Python CI 校验）。本地：video 788/788 + lab 298/298 + 矩阵测试 4/4、analyze 零 finding；hosted source checks 该头 success。V1 复核 0 blocking（observed 恒 null 结构性保证、重建走正常门、矩阵与 §4.3 逐格一致）；29→28 笔误已更正；C2→C4 续走依赖层不可表达为记录在案的后续项。B1/B2 原生前置：需 HDR10+/Vivid 样片与 FFmpeg/mpv dirty 对账。context：方案 §11 回执。
- 2026-10-14 §10.3.5a experimental 字段整体删除（routing@0c1ee051+，media_kit 侧）：`HdrRoutingPolicy.allowExperimental/experimentalWasSpecified` 与 `VideoRouteOptions/EffectiveVideoRouteOptions.experimental` 全链删除；序列化迁移契约=fromMap 保留 legacy key 静默丢弃（一次迁移）、toMap 不再输出（契约测试钉住）；session `_legacyPolicy` 死字段删除（setPolicy replan 语义保留）；Lab 调用点去参；16 测试文件同步（参数化循环折叠 808→783，逐文件核对无断言本意删减）。验证：video 783/783 + lab 298/298、analyze 零 finding。范围外：`video_player_media_kit/analysis_options.yaml` 一处非本批改动保持 dirty 待用户裁定；PiliPlusX 侧迁移另批（pin 更新与提交须待主库推送）。
- 2026-10-14 LG P8.4→PQ 重开诊断收口并按最新 tip 重验（用户指令"诊断并制定打通方案"，后追加裁决"两 define 删除、功能直接开启"）：结论=三轮（lgh4/lgh5/lgh6）同点失败为**载体未接线**，非候选模型回归——C4 realize 为 mediacodec-copy 通用窗口（format 278）被 vendor 窗口门拒绝（window-format-not-43-experiment-disabled），且 DV 序 C2 先行，其硬编码 RGB 构型在 LG（RGB 链无 HDR 呈现路径，10-09 根因）结构性不可行，运行期 dataSpaceApplyFailed 后 dataspacePq 依赖级联排除 C4。hdr10/p5 在 LG 正常因 mediacodec_embed 直通不经过渲染窗口 dataspace 通道；native 能力核验在位（lib 槽 5f8fc04c 字节一致、surfacetexture 对象在构建物、vendor config49 与 arm 通路代码全在）。**d07b46b3 重验**：497bf0b2 已隔离 mapperDolbyVision 依赖（mapper 失败不再影响 C4/C3），但 LG 失败类是 dataspace、dataspacePq 仍被 C2/C4 共享且级联语义被契约测试钉住——W1 计划门仍必需；C2 构型（realizer:487-491 硬编码 RGB）与 dvP84 默认序未变。方案 v3=LG dvP84 走 C4 baseLayerConvert（HLG→PQ）× YUV config49 HWC 窗口载体，RGB/YUV 判定升级为**声明式 PQ 呈现通道能力模型**（用户裁决"走线自动按能力确定"）：vendor ext 自报 `pqPresentation{rgbSurface,yuvWindow}`（LG 报 {false,true}）+ 平台默认（API≥28→rgb）+ 迁移默认（旧 adapter→{true,false} 现网逐位不变）；消费规则=C2 要求 rgbSurface（false→计划期不可行，取代 lg-pq 特判）、C4 载体按通道推导（yuv→surfacetexture+config49 契约，否则平台基线）；W2 两 define 删除功能直开（载体推导取代 v2 无条件翻转、mkst probe 死代码清理、lab arm 塌缩到运行时守卫，爆炸半径较 v2 收窄）；W3 host 绿；W4 实机验收（SF 实锤 config49 层/COLOR_METADATA/人工三样）；W5 记录收口；不恢复 SDR 兜底、不改候选序全局裁决。唯一待裁决 W1b（依赖键通道化 dataspacePq@rgb/@yuv 同批 vs 后续——mapper 隔离同构扩展，无双通道设备时两案实机行为等价）。完整诊断与方案：`docs/plans/lg-p84-yuv-window-reopen-20261014.md` v3（未提交）。
- 2026-10-15 LG P8.4→PQ **实机打通**（lgh8，方案 C 演进 + V2 五轮后装机）：主判据 8/8 全过——能力自报 pqPresentation{false,true}、C2 skip=pqRgbPresentationUnavailable、C4×surfacetexture 选中、桥初始化成功（对照 lgh7 bridge-not-initialized 消失）、**复核样本 hwdecCurrent=surfacetexture**（lgh7 为 null）、config49 分支+lgPqApply 全链 accepted 零 refused、verified=true 274s 连续（decoder-frame-drop=0）、SF 实锤 config49 HWC 层（7FA30C04）持续驱动+hal_hdr 驻留+COLOR_METADATA(9,1,16)、SDR 复位干净。回归：lgh8-sdr **零 YUV-DIAG/config49 行**（对照 lgh7-sdr 被 arm 毒死——方案 C 直接验证点）；p5 nativeDV/hdr10 baseLayerDirect 零 arm；同进程 p84→dispose→p84 重验（bridge 重初始化、无原子残留、无 single-open 误触发）。**实施演进**（lgh7 暴露方案外缺陷，Specialist 裁决方案 C + V2 五轮审核收敛）：①arm 生命周期归生产库按 attempt 路由条件化（HdrYuvWindowArm + ProcessOutputInitGate Java 进程静态读写门跨 engine 仲裁：准入先于 retirement、arm 在 retirement 后 create 前、attempt 终结 awaited 清理、cleanup debt 与写锁同生共死、lease 身份绑定参与者）；②桥 init owner token 改能力门控并补齐标准构造路径接线；③lab 预开 arm 仪式退役；④leaseId 通道 Number 化（V2 真实 codec 探针抓得 Integer→Long CCE）。host：video 878/878、lab 292/292、Chrome 77/77、vendor JVM 37/37、analyze 双 0。遗留边界：production owner 自动生命周期另包（生产 YUV 路径无 owner 早期显性失败）；wrongHint/跨源互切设备场景待专建；人工三样待用户目视；W1b 未实施（无行为需求）。证据：`~/src/media-kit-build/evidence/lg-p84-reopen-20261014/`（lgh7 失败链+lgh8 全套）；方案 `docs/plans/lg-p84-yuv-window-reopen-20261014.md` v4 + spec-c 裁决书。API 契约文档同步（需求文档 R1 能力清单补 pqPresentation 三来源与消费规则、降级理由枚举补 pqRgbPresentationUnavailable/yuvWindowArmUnavailable 与进程门设备限制）。 LYA 回归补测（2026-10-15 lyagh8-p84）：**PASS**——C2 reshape→PQ 与 v73 基线同构（ext:lya-pq、readback=DATASPACE_BT2020_PQ、SF BT2020_PQ 层、316s 连续零丢帧、dispose 闭合）；能力模型第二实机数据点：LYA 显式自报 `{rgbSurface:true, yuvWindow:false}`（与 LG {false,true} 互补），RGB 通道设备零误伤；零 arm 零毒化语义成立（MKSURF verify-only 探测 2 行与 v73 通过基线逐字同、无副作用，字面留档）；设备原状还原（原未装包→uninstall）。jason/marble/ugg 仍待在线补记。

## 接手快照（2026-10-10 更新；换 agent 从这里开始）

- **事实源与范围**：本文件是任务状态；`archives/README.md` 是主题导航。主题上下文（各 conversation 顶部 Current State）：Android HDR/P5 主线 `archives/conversations/android-hdr-dv-display-plan-20260922.md`；LG/marble 线 `archives/conversations/lg-h870ds-hdr-demo-20261004.md`；整改主题 `archives/conversations/architecture-review-remediation-20260930.md`。LG followup 单一计划=`docs/plans/lg-p84-hdr-followup-plan-20261009.md`（v4.1，全部出清，触发式候选/重开条件在案）。接手后先重读 Git/设备状态，快照仅是入口。
- **代码状态（四仓库，2026-10-10）**：① media-kit `main` tip `788fc3b2` 已推送（followup v4.1 收口/G1/C3/回归轮收口+测试构建默认正式化+台账精简并入+experiments 存档入账）。② mpv fork `media-kit/android` tip `c11426b67a` 已推送（native DV bridge 内省/surfacetexture 直连/demux hvcc 补全/Vulkan Properties2/render-mode opt-in 五提交）。③ FFmpeg 分支 `lg-p84-d1-vui-fix-20261010`（`d4bb79394b`）已推送；Kazumi HLS 广告补丁不入库（留构建树+genbump 溯源，prefix 重建须有意识携带）；configure hack 不正式化（G1 裁决，清空 dirty=常态机制，字节门验证窗口保持两树清空）。④ libplacebo fork 现役分支 `optimize/dovi-linear-decode` tip `ea700489`（基点=上游 `d4624cbf`，4 提交：dovi linear decode/gamut clip/EXTERNAL_YUV/rgb10a2+float32，external_yuv 内容=`980742df`+`ea700489`）；构建树 `buildscripts/deps/libplacebo` 实际消费仍为旧钉定 `c9fd8798`（detached HEAD，2026-10-11 核验），该哈希经 2026-10-01 分支重建已不在任何远端、仅 `~/src/libplacebo` reflog 可达，按哈希 fetch 会失败；同日核验上游无强推，fork master 已快进同步上游 tip `1dd02268`。发布链钉定 v2026.013（2026-10-11 vkweak）=v2026.012 二进制+Vulkan 1.1 两导入弱化（0e06f383…）=mpv `d24c59905b`+FFmpeg `b4d2ea4` 世代，build.gradle/CHANGELOG 已同步；本地测试构建已整体切 genbump prefix 代际（2026-10-10 起，见环境条）。
- **环境与设备**：ADB 双机——**marble（Redmi 23049RAD8C，dede0cd2，API 35/HyperOS）现役 DV/HDR 实机**（displayHdrTypes [1,2,3,4]、c2.dolby.decoder.hevc 声明 profiles 32/16/256、bridge api 1；素材 p5 dacfd045 / p84 7626cac2 已推送核验，2026-10-10 晚补推 p5-mystery-box（3e610d3b）/hdr10-full（e4f869b1）并建 p84-full 规范名副本（7626cac2 同字节）；现装包=r30g（3968e6fc，2026-10-10 21:53 双机回归后还原并字节核验，自动亮度/熄屏已恢复））；LYA-AL00（3EP7N18C28016072）备用。持久化资产：`~/src/mpv`（fork 工作树）；`~/src/media-kit-build/`（jars/apks/evidence/scripts、`lg-api24/` 管线、`LG-DEVICE-LOGCAT-PROTOCOL.md`——本 ROM 交互式 logcat 为空必须 exec-out，设备侧 md5sum 可用/sha256sum 不存在、MKS_DEFINES_OVERRIDE=合并语义、槽位换 .so 须 store+zipalign -p 4096）；`product-ffmpeg-lib/`（fff3ee7 世代持久副本）；整改产品 JAR `media-kit-remediation-final-product.jar`。构建：JDK17（`JAVA_HOME=/opt/homebrew/opt/openjdk@17/...`，勿改全局 Flutter 配置）；`ORG_GRADLE_PROJECT_mediaKitLocalArm64Jar` 为 gradle 正式本地 JAR 注入通道。**测试版构建默认（2026-10-10 裁决，全文在 AGENTS.local.md）**：Android 测试包一律 `tool/build-android-test.sh`（最新源码 ninja→JAR→APK 三步自动），钉定下载 JAR 仅用于发布构建与发布链回归。push 一律逐次请示（osxkeychain 挂起时用 `git -c credential.helper= -c credential.helper='!gh auth git-credential' push`）。2026-10-10 四库当前分支 upstream 已设齐，分支内裸 `git push` 可直达：mpv=origin/media-kit/android（原 fetch refspec 钉死旧分支，已修为全分支并补全跟踪引用）、FFmpeg=origin/lg-p84-d1-vui-fix-20261010、PiliPlusX=personal/fix/darwin-video-output-rebuild-barrier（origin=上游 cnctem 无写权限，勿改指向）、flutter-ohos=github/ohos/media-kit-patches（origin=gitcode 源）。
- **LG/marble 工作线已收口（2026-10-10）**：P8.4 HLG"色彩淡"根因=显示链按 SDR 方式处理 PQ 码值（面板 PQ 能力在，RGB GLES 链无 HDR 呈现路径）；修复=YUV config49 NV12 HWC 视频层+逐 buffer COLOR_METADATA+BT.2020 NCL 打包（HLG→PQ），人工验收通过；P5 直通默认化（dvP5×nativeDV verified）；A 组三格成熟度提升；followup 计划全部出清。详见 Recently Done 对应条目与 followup 计划。
- **双设备最新代码回归轮通过（2026-10-10 晚，LYA+marble 六轮全绿）**：main `a072e964` + mpv HEAD `c11426b67a`（含 5 未推送提交，实际重编译——12:01 genbump2 JAR 缺下午提交内容，"18:02 一致"验证未完成链接）+ FFmpeg `d4bb79394b` 重建 JAR（槽 5f8fc04c，链接字节级可复现）；**dvP5/dvP84×nativeDV 在 marble 默认策略（无 GATE）首次真机直达**（P5 全片丢帧 1 次，直通流畅再证）；LYA 三路由全 verified（P5 reshape→PQ/HDR10 baseLayerDirect/P84 HLG 直出，DV=false 预期）；render_failures/fatal 恒 0。报告：experiments `regression-two-device-latest-20261010.md`（4c65217）；证据本机 `~/src/media-kit-build/evidence/regression-two-device-20261010/`；conversation `archives/conversations/regression-two-device-20261010.md`。
- **设备待办两项（2026-10-10 用户指示入待办，非回归失败，排查待用户裁决）**：①LYA P5 reshape→PQ 稳态 VO 丢帧偏多且轮间差异大（发布 JAR 稳态 8/60s vs 最新 30/60s、复测轮 t≈40–60s 突发 329；decoder 恒 0——4K59.94 gpu-next 重建在 Kirin 980 吞吐边缘，是否 5 个 mpv 新提交加剧未定论）；②marble post-EOS BACK 不触发 dispose（app 侧零日志，三次 P5 全片轮复现含最新构建；同机 pre-EOS 正常、LYA post-EOS 正常——签名 HyperOS API35 × post-EOS 状态。2026-10-13 修正：LG(API24)/jason(API35) p5 全片轮同签名复现，原归因不成立改设备相关待查；marble pre-EOS hdr10 一次 NO_DISPOSE 不作数——同轮复核门已竞态失败）。证据同上目录（lya2-p5/lya2-p5b/marble2-p5 device.log 帧计数序列）；2026-10-13 扩展证据同新目录。
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
  - HDR10+/Vivid 样片（2026-10-14 入库，B1/B2 验证材料，ffprobe 帧级定性）：`~/Downloads/test-clips/HDR10Plus_PA_DTSX.mkv`（SHA-256 `9fc54031…`，HEVC Main10 4K PQ，HDR10+ SMPTE2094-40 逐帧）→LG `/data/local/tmp/media-kit-hdr10plus-pa.mkv`；`HDR10Plus_PB_EAC3JOC.mkv`（`c751f824…`，HDR10+ Profile B，备用）；`4kHdrVividDemo.mp4`（`f9b0a569…`，Vivid CUVA 005 4K PQ）→LG `/data/local/tmp/media-kit-hdrvivid-pq.mp4`；`hdr-vivid.mp4`（`18c7c05a…`，Vivid CUVA 005 4K HLG）→LG `/data/local/tmp/media-kit-hdrvivid-hlg.mp4`；`vivid20240702001.mp4`（`8701fbe9…`，Rext 1080p 备用）；`SonyBraviaOLED4KDemo.vivid_bd265_4k.mp4`（`4e1b9331…`，采样窗未见动态元数据存疑备用）。FFmpeg@~/src/FFmpeg d4bb79394b 与 mpv@~/src/mpv c11426b67a 工作树就绪（B1/B2 C 代码可开工）。**用户裁决（2026-10-14）：两制式缺失功能列待办项**；过渡态=报日志、走兼容基线（HDR10+→静态 PQ 基线、Vivid→静态 PQ/HLG 基线，动态 C1/C2 不合成）——LG 复跑实证：vivid-pq 3/3 走通 EOS、vivid-hlg 2/2 确定性阻断于 LG PQ 输出缺口（同 p84 族）。待办基础=B1 缺口地图（归档 2026-10-14 B1 审计段，实施顺序三步在案）。**HDR10+ reshape（C2）前置条件（2026-10-14 用户裁决）：hwdec 逐帧元数据交付工包**（mediacodec_dovi 模板泛化：SEI 2094-40/CUVA005 输入解析 + pts/epoch 跟踪 + 输出附加；configure 补 hevc_sei select）——实证根因链：样片 SEI 仅在码流内、hwdec 无解析→属性恒 false→分类恒 none→reshape 无输入。
  - latest: **四仓库归一后播放矩阵六轮全部通过（2026-09-30，12703–12708）**：P5/P8.4/HDR10 × SDR/HDR，全片 EOS（P8.4 为 5 分钟观察窗），输出路径全部符合预期，零渲染错误、资源闭合全对等。证据 `archives/experiments/android-playback-matrix-12703-12708-20260930.md`。第二台设备（Redmi Note 5A，骁龙 425）同矩阵不可行并按用户要求中断（OMX HEVC 不支持 4K、屏幕无 HDR）；第三台设备（Mi Note 3，骁龙 660）4K Main10 硬解/直采/EOS 通过但展示链路 VO 掉帧 84%，EOS 尾帧一次取图失败且回退未触发（设备差异观察项，原因未查）——均见同文件追加节。此前 HDR10、P8.4 全屏画质和流畅性已获用户认可；首帧读回 P8.4 HLG 0.623–0.676s、HDR10 PQ 0.630–0.653s（Surface 读回，非面板光学）。
  - next: 扩充原生 HDR 冷/热、重入、连续帧及 SDR 复位证据；P5 输出和首帧单列于 P1，不以 HDR10/P8.4 代替；P8.4 全片 EOS 按需补跑。可与 4K60 冷机复测（2026-10-02 归因轮唯一残余）合并同一 LYA 会话。
  - latest+ (2026-10-03 凌晨，新 JAR b4d2ea4 世代)：**SDR 复位 ✓**（HDR 轮后 sdrDirect texture 路由、无 HDR 残留、两轮一致）；**冷启动首帧 ×3**（tap→trigger→decoder 事实 verified ~0.6s→路由 applied，路径 ext:lya-pq + SF 读回 BT2020_PQ）；热重入部分（BACK+tap 未触发二次 open，自动化限制；A4 九轮语义证据在旧世代）；系统化冷/热百分位与 4K60 冷机复测顺延（设备整夜解码热负载）。证据 `archives/experiments/android-ffmpeg-p5-rpu-b4d2ea4-verify-20261003.md` app 通道节。
  - next+ (更新): 冷/热百分位矩阵与 4K60 冷机复测待设备冷却后补（可与下次 LYA 会话合并）；重入复跑待 PiliPlusX 长按钩子或人工路径。

- [ ] HDR lab 测试效率改造：一次构建 + 运行时场景 + 批量测试
  - status: in_progress（总体方案已产出并完成用户裁决，待启动 WP0 实施）
  - context: docs/plans/hdr-lab-runtime-scenario-batch-20261011.md；archives/conversations/hdr-lab-runtime-scenario-batch-20261011.md
  - latest: 2026-10-11 team-specialist 只读核查产出总体方案（HEAD d7619227），Lead 复查抽查通过。两处纠偏：lab 编译期开关实为 150 处/139 key/6 文件（主页面 126）；生产库 media_kit_video 直接消费 5 个同名 define（realizer CONVERT_SURFACE_TRANSFER/CONVERT_ROUTE_LOCK/SURFACETEXTURE_POC、session SURFACE_FORMAT、review REVIEW_TRACE）——"一次构建"按 build identity 划界，build-bound PoC 变体保留独立构建。分期 WP0 清单冻结（0.5–1 人日）→ WP1 运行时配置（3–5+1–2 人日，含 build-android-test.sh runtime-lab 模式）→ WP2 batch 一次启动整批（5–8+2–3 人日，host watchdog + app 私有目录落盘 + adb 镜像）。**用户裁决（2026-10-11）**：① 接受 build identity 划界；② 故障批允许自动重启恢复（attemptId 显式）；③ 结果写 app 私有目录+adb 镜像；④ A3 扩展注销留在构建期、不纳入 WP1（WP1 Kotlin 范围收缩）。
  - acceptance: WP1 后同一 APK（同一 build identity）经启动参数切换普通场景/源片/hint/观察窗零重建，无配置基线与旧无 define 包一致，拒绝路径不静默回退；WP2 后一次启动按 manifest 顺序跑整批，N case 恰 N 终态，单片段失败不阻断，硬挂死由 host watchdog 恢复，结果镜像 pull 后 hash 一致；两期共同硬验收：生产库与 PiliPlusX 零 diff、证据协议按 manifest SHA + LAB_SCENARIO 行绑定、139 key 默认值逐项一致。

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
  - status: in_progress（Web快照与全等URI循环修复已实现；完整duplicate occurrence/队列编辑仍开放）
  - context: archives/conversations/media-kit-routing-20261011.md；docs/plans/core-lifecycle-bootstrap-host-ci-checkpoint-20261012.json；历史 archives/experiments/ci-fix-20261002.md
  - acceptance: 快照不被后续shuffle修改；等值队列保持当前occurrence/index且不死循环；定向与完整Chrome结果分别绑定准确源码。
  - latest: a73d570b实际Web定向4通过、full63通过/27跳过；4d1d新增两项形成定向6。新general38275707106@4d1d已实际运行；Web定向步骤16:46:55–16:47:22的metadata为success，完整Chrome从16:47:22继续执行。预期6项的实际case日志尚未取得，不能称已读6通过或full完成。 Native历史随机测试修复保持。
  - next: 核完当前定向6及full；混合重复URI、增删队列与恢复映射另行认领，不能以全等队列修复代替。

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

- [x] LG P8.4→PQ 显示重开实施（C4×YUV config49 HWC 载体）：done（2026-10-15 lgh8 实机 PASS；机器判据全闭，人工三样待用户目视）
  - context: 方案 v4 `docs/plans/lg-p84-yuv-window-reopen-20261014.md`（含 §0 实施验证回执）+ spec-c 裁决书；实施演进=方案 C（arm 生命周期归生产库按 attempt 路由条件化）+ token 能力门控接线 + lab 退役；lgh8 全套证据 `~/src/media-kit-build/evidence/lg-p84-reopen-20261014/`
  - acceptance: 机器判据已全闭（lgh8 八条 + 回归 + 互切 + V2 五轮）；开放残留=W1b（dataspace 依赖键通道化，无行为需求）、wrongHint/跨源互切设备场景专建、production owner 自动生命周期另包、人工色彩/亮度/流畅三样待用户目视。
  - next: 用户目视三样（LG 上 p84：色彩/亮度/流畅对照 10-09）通过即全闭；LYA/jason/marble/ugg 回归待设备在线补记（非代码失败）。

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

- [x] arm64 libmpv 钉定升 v2026.013（vkweak）：done（2026-10-11）。v2026.012 资产字节级派生，仅 `vkGetPhysicalDeviceProperties2`/`vkGetPhysicalDeviceQueueFamilyProperties2` 未定义导入 GLOBAL→WEAK（字节差=2），修复 minSdk 24 设备（系统 libvulkan.so 仅 1.0）dlopen 失败——LG H870DS（Android 7.0）app 打不开根因的库侧正式修复；实机 dlopen+OMX.qcom avc 硬解 Executing+像素差分帧推进+切后台恢复通过。派生工具/断言/打包接线：Goodwu/libmpv-android-video-build-dv-experiment@72c574d（bundle_default 四 ABI 内置弱化，`make_vkweak_release_jar.sh` 派生发布资产，契约=产品 Android 拓扑不建 Vulkan 上下文，vo=vulkan 需恢复强符号+API 28+）。release：`libmpv-android-v2026.013`（0e06f383…）；gradle URL/SHA、包 CHANGELOG build-lock 段同步；PiliPlusX 侧启动容错+实机验收见其 `archives/conversations/android7-lg-h870-launch-playback-20261011.md`。

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


- [x] 加入 Debug 编译源码约束（2026-10-12）；仅文档核验，未构建、未提交；Lead V0 核验通过，git diff --check 通过。context: archives/conversations/debug-build-source-policy-20261012.md
