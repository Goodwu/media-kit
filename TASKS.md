# TASKS.md

任务事实源：这里只保留当前状态、验收门槛和下一步。2026-09-27 清理前的完整实验流水保存在 `archives/experiments/tasks-ledger-snapshot-20260927.md`；按各项 `context` 查看持续更新的依据。

## P5 当前优先级（2026-09-28）

P5→PQ 输出、首帧和性能使用 `/Users/wuweiwei1/Downloads/test-clips/Mystery Box Dolby Vision Profile 5.mp4`，SHA-256 `3e610d3b1b11e9b802da66d69bd97f6371a2b114ee464a7e8517fe31d706cc9f`；HEVC Main 10、3840×2160、60000/1001 fps、DV Profile 5/RPU、98.944 秒。用户确认片头无黑场。P5→Texture SDR 默认优化验收继续使用原 Glass P5 4K59.94（SHA-256 `afb24b77733a3ca9071f0cfea0d0f7871670a7b6119eb44a314cba974541477c`）与旧同片结果对照；按用户补充，Mystery Box 也另测一轮 Texture SDR 全片基准，后续同片复测。Glass 仍保留作片尾紫屏定点复现。

1. **P0 P5→Texture SDR 优化默认开启并验证**：先把已保存的通用 `optimize_dovi_linear_decode` 候选接入支持条件下的默认路径，保留不匹配场景回退；验证自建 arm64 JAR 确实含优化、Glass 实际命中、短轮画质/资源和全片观感。同片同尺寸默认电池模式的既有优化轮 EOS VO 516、t90→t180 新增342作为参照，新构建性能相近、无明显回退即可，不再追逐旧严格掉帧门槛，也不要求 PQ 等待额外的 SDR 调优。
2. **P1 P5→PQ 产品输出和首帧**：公开 Android 输出链路为主目标，以新片确认正常入口横屏全屏出画、10 位 BT.2020/PQ 合成及点击到可见内容；精确固件私有方式仅作公开路径确实无法打通后的备选，不将诊断探针直接作为产品完成。首帧探针绑定当前 Surface 代次，不借旧片黑场推断延迟。
3. **P2 P5→PQ 全片性能**：新片在默认电池模式、明确输出尺寸下播至 EOS，逐段记录 VO/decoder 掉帧、GPU 频率、温度及持续画面；据此优化 PQ 路径。P5→Texture SDR 的 RPU/线性解码及安全回退代码可作为共用候选，但旧门控与实测收益不能外推；先核新通用分支在 PQ 目标的命中/颜色，再同包 A/B 量化收益。
4. **P3 P5 生命周期及片尾问题**：覆盖退出重入、Surface/双视图切换、Engine 销毁；旧 Glass 紫屏继续按定点故障复现，新片仅作正常 EOF 回归。
5. **P4 独立色彩数值验收**：用户已看过 P5 画面，认为颜色基本正常；保留 RPU 逐帧/seek/flush 及独立同 PTS 数值比较，排在输出、性能和生命周期之后。

## Now（当前推进，最多 3 条）

- [ ] Android HDR10 / DV P8.4 / P5 显示闭环
  - status: in_progress
  - context: archives/conversations/android-hdr-dv-display-plan-20260922.md
  - acceptance: 固定素材身份与设备能力；PlatformView 对 HDR10/P8.4/P5 分别输出 PQ/HLG/PQ，Texture 明确转换到 SDR；核对实际后端、Surface 格式、系统 HDR 合成、SDR 复位和全屏可见画面。P8.4 的无 HLG 路径、P5 DV 元数据处理及原生 DV 能力须单独说明，不能以 PQ 转换冒充原生 DV。最高亮度仅用于短时人工观察，每轮结束立即恢复原自动亮度，不长时间停留静态画面。
  - latest: HDR10、P8.4 已获用户真全屏画质/流畅性好评；10436/10437 P5 同页全屏画面良好。12542/12543 在精确固件私有探针开启时再次得到 P5 `gpu-next`/`mediacodec`、10 位 BT.2020/PQ 视频层、HWC PQ 合成和全屏实际画面；这是本机诊断路径成功，不是通用产品路径通过。12539 仅是关闭探针的公开 Surface PQ 设置失败（`wid=0`）。此固件普通应用 GPU producer 的已试公开 PQ 出口均失败，11009 AHardwareBuffer 同样因 HDR 能力权限拒绝 SIGABRT。12541 私有设置成功却被旧 Surface 的颜色空间 ACK 错误拦住，12542 通用修复后出画。12468 P5 失败后同进程原生 `mediacodec_embed` HDR10/P8.4 依次恢复；12471 再接 SDR 时视频层复位 BT.709、HDR metadata types=0，见`archives/experiments/android-hdr-sdr-recovery-12471-20260927.md`、`archives/experiments/android-p5-private-pq-firstframe-12541-12543-20260927.md`。默认产品 P5 PQ、静态元数据、独立色准及全屏双视图一致性仍开放。
  - P5_RPU_color_gate: 用户已观察 P5 画面并认为颜色基本正常，独立色彩数值验收降至 P4；仍需对实际输出逐帧核对RPU与画面，覆盖seek/flush/重开，并以明确参考母版、目标空间和映射策略做同PTS独立比较。10440前后跳4次flush匹配2321/2321；12512预建路径两次重开匹配626/626、622/622，errors0/unconsumed0。长期重开、该布局seek/flush和独立色准仍开放，见`archives/experiments/android-p5-glass-rpu-reopen-12486-20260927.md`、`archives/experiments/android-p5-glass-prebind-rpu-12512-20260927.md`。
  - next: 先完成上方 P0 的 P5 Texture SDR 默认优化集成与验证，随后寻找受支持的公开 Android PQ 输出链路，验证真实全屏画面、系统合成及 SDR 复位；已证实失败的同一公开 setter 不作无变化重复探针。私有固件探针保留为公开方案走不通时的受限备选。RPU/独立色准按上方 P4 排序；P5 Texture SDR 仅作明确标示的降级，不关闭 PQ 任务。

- [ ] P5 性能：先将 Texture SDR 候选默认开启，再测 PQ 全片
  - status: in_progress
  - context: archives/conversations/android-hdr-dv-display-plan-20260922.md
  - acceptance: P5→Texture SDR 使用指定 Glass 片，在与既有优化轮相同的真横屏2560×1440、默认电池模式下播至 EOS，确认通用优化默认命中、回退、资源闭合、画面观感，VO 掉帧与既有优化结果相近；另用 Mystery Box 做同配置全片基准及优化后同片复测。记录GPU频率以避免不同降频条件下误判回退，不再要求旧严格掉帧门槛。P5→PQ 用 Mystery Box，在明确输出尺寸、默认电池模式下记录逐段 VO/decoder 掉帧、媒体时间、GPU频率、温度及持续可见画面，再定向优化；两片数字不互作基线。
  - latest: 同 APK、2560×1440 输出的系统性能模式开/关/开 EOS VO 掉帧为 17/5051/19，decoder 为 0；默认模式门槛未过。1920×1080 也出现伴随 GPU 低频的后段失速；关闭抖动无明显低频收益，已停止该方向。用户最近确认 10437 的 1440 宽 P5 吹玻璃画面流畅，但这不覆盖 2560 默认模式全片门槛。
  - output_scope: 既有 `p5_pq_pipeline` A/B/A 在 **P5→Texture SDR BT.1886、2560×1440** 下取得 EOS VO 2607/516/3626，严格门槛仍失败；其分支明确要求 SDR 目标，不能用于 P5→PQ Surface。12542–12544 的 P5→PQ 使用自建 JAR `f745146...`，其中没有该分支，短轮只证出画与合成，尚无同配置全片掉帧数据。原生 PQ 的性能须单独定目标尺寸和默认电池模式，用同一正式输出路径播至 EOS 记录 VO/decoder、GPU 频率及真人流畅度，不能沿用 Texture SDR 数字。
  - mystery_sdr_baseline: 12546 未含线性解码候选的 arm64 自建 JAR，Mystery Box/Texture SDR/2560×1440/真横屏全片到 EOS：VO累计54、decoder0；媒体约2.47/34.47/64.46/94.48秒累计45/47/51/54。100个播放起点后GPU样本的中位586MHz，76个586MHz、19个644MHz；热状态1。与低频的旧Glass优化轮不可直接比，也不代表 PQ 性能。截图有实际画面，未作真人流畅度观察。见`archives/experiments/android-p5-mystery-sdr-baseline-12546-20260928.md`。
  - next: 先把已提交到 Goodwu/libplacebo 的候选通过受支持的 P5→Texture SDR 策略默认启用，构建自有 arm64 JAR 并验证命中、回退、资源和实际观感，不展开旧 Glass SDR 掉帧调优。公开 PQ 产品链路可用后，用新片测全片基线，区分 GPU 渲染与提交/合成等待；复用 `optimize_dovi_linear_decode` 时另核 PQ 目标的真实命中、同PTS颜色和同包 A/B，不能沿用 SDR 掉帧收益。

- [ ] Android 视频首帧时延验收：先 P8.4 Texture SDR，后原生 HDR
  - status: sdr_accepted_hdr_in_progress
  - context: archives/conversations/android-hdr-dv-display-plan-20260922.md
  - acceptance: 第一阶段以用户指定、片头有画面的 P8.4 全片，从用户触发正常打开至手机实际显示视频内容小于2秒、争取1秒；记录冷/热分布与最慢样本，验证全屏、Texture→SDR色彩/音画同步、退出重入。第二阶段独立测固定HDR10/P8.4的原生PQ/HLG真全屏首帧、Surface dataspace/系统合成和持续画面，超2秒则同包对照并优化。另对P5自身转PQ HDR输出单独测量；该机公开PQ出口目前受固件权限阻断时记录失败阶段与耗时，不以HDR10/P8.4代替P5结果。
  - latest_sdr: 12528同APK物理全屏Texture→SDR、独立进程关→开→关→开→关→开，点击回调内PixelCopy明显内容关闭2.049/1.697/1.740秒、开启0.884/0.892/0.894秒；另一次开启0.814秒并截图确认视频。同包预绑定三对均值差约0.939秒。受控短轮不覆盖触摸/面板光学、正常入口、音画及重入，见`archives/experiments/android-p84-firstframe-prebind-ab-12528-20260927.md`。
  - normal_entry_sdr: 12530已挂载Video的普通竖屏列表入口，独立进程四轮点击回调内PixelCopy明显内容0.681/0.462/0.449/0.454秒；四轮通用Texture预绑定均为layoutBound=true，间隔截图证明连续画面。重复点击的首个探针采样为旧帧，不能算重开时延。仍缺触摸起点、真全屏、音画和有效重入，见`archives/experiments/android-p84-normal-texture-firstframe-12530-20260927.md`。
  - tap_fullscreen_sdr: 12531普通列表点击后，同一Video进入物理横屏全屏、布局完成再预绑定并打开；独立进程四轮点击回调内PixelCopy明显内容0.863/0.664/0.656/0.663秒，均layoutBound=true，间隔3秒截图为不同视频帧。全屏Back后再次打开可重新出图，但旧帧污染重入计时。仍缺触摸派发/光学、独立色彩、音画同步与有效重入首帧，见`archives/experiments/android-p84-tap-fullscreen-firstframe-12531-20260927.md`。
  - touch_to_content_sdr: 12532 Activity触摸抬手至横屏全屏PixelCopy明显内容三独立进程0.792/0.699/0.670秒，均通用预绑定成功；仍不含按下至抬手及面板光学呈现。见`archives/experiments/android-p84-touch-to-content-12532-20260927.md`。
  - touchdown_reentry_sdr: 12533三独立进程触摸按下至横屏全屏明显内容0.767/0.789/0.681秒；12535同PID先销毁播放页、回主菜单，再新建播放页并出图，第二次按下至内容0.656秒，旧帧不再污染。仅系统读回短轮，仍缺光学、独立色准、音画同步与冷/热统计。见`archives/experiments/android-p84-touchdown-and-reentry-12533-12535-20260927.md`。
  - sdr_acceptance: 12535 P8.4 Texture→SDR 真横屏全屏人工观察：用户认为轻微偏淡但可接受，画面流畅、声画同步；单独从竖屏列表 Video 0 点击，用户感受约1秒内出实际画面，同轮触摸按下至明显内容 PixelCopy 为0.844秒。此前一次约2秒竖屏黑屏反馈含脚本故意等待2秒，不能归因于播放器。此设备/素材/路径的用户验收通过；未做独立色度仪或面板光学时间测量。见`archives/experiments/android-p84-sdr-human-acceptance-20260927.md`。
  - latest_hdr: 12537 P8.4原生HLG三独立进程触摸按下→视频Surface读回内容0.670/0.676/0.623秒；12538 HDR10原生PQ为0.653/0.648/0.630秒。各有真横屏全屏截图，SF视频层分别BT.2020 HLG(types0)/PQ(types3)。12539 是关闭私有探针的公开 P5 PQ 设置失败，`wid=0`，请求→明确失败0.422秒。12542/12543 在精确固件私有探针开启时成功输出 P5 PQ 并出实际画面；12543 三独立进程触摸按下→读回可辨内容3.953/4.009/4.079秒，含片源黑场，且首次探针采样曾命中旧 Surface，尚不能当作精准首个解码帧时间。2秒时视频层已有 PQ activeBuffer，截图仍是片头黑场。视频Surface读回可作自动化时延门槛，但不能单独证明系统合成或面板显示。见`archives/experiments/android-native-hdr-firstframe-12537-12539-20260927.md`、`archives/experiments/android-p5-private-pq-firstframe-12541-12543-20260927.md`。
  - next: P5 改用上方无片头黑场的 Mystery Box 样片重测 PQ 点击到可见内容；12544 的3.967秒属于旧片，不能沿用。探针绑定当前 View/Surface generation，区分首个 HDR buffer 与可辨画面；评估可支持的产品出口，不重复已证实失败的公开 PQ 探针。扩充 HDR 冷/热、重入、连续画面和输出切换统计；面板光学及独立色度仪仍是精度限制。

## Next（近期候选，最多 10 条）

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
  - latest: P8.4/HDR10/SDR 的 Home→返回、双视图存活 B 回退、释放/绑定失败重试已有实机可见画面证据。12473/12474/12475受控SDR交错核验旧A的Available/Destroy晚到与ACK回复超时；12477旧A Failed注入后B成功出HDR10画面。12486 P5长播后重入在Flutter SurfaceTexture finalizer release栈出现一次SIGSEGV，归因未明。测试页自动单播放器 Back 现等待输出/Player清理；最终包12492 P5推进至媒体PTS164.8秒、早晚截图均有不同实际画面，Back时输出/Player完成早于Activity退出，同一PID重入再次出图且无SIGSEGV；未播及短播返回亦正确，V1复审无阻断，见`archives/experiments/android-auto-player-exit-12491-12492-20260927.md`。片尾另见纯紫色区域，已单列；任意Engine直接destroy仍未验。注入均已撤销，提前停轨仍默认关闭；完整历史见本条 context。
  - p84_scope_exit: 12534暴露测试页普通Texture SDR退出时错误要求HDR清理报告，12535修正后同PID完成全屏→返回→播放页清理→主菜单→新页再出图。清理约5.1秒已定位到NativePlayer.dispose中刻意等待的5秒终止宽限期，非本轮新卡顿；保持既有终止屏障。见`archives/experiments/android-p84-touchdown-and-reentry-12533-12535-20260927.md`。
  - next: 核验清理中再次点击、失败重试和全屏组合。任意宿主直接 FlutterEngine.destroy 需先做独立于 Dart 的 Android 原生播放器 owner broker，统一 mpv 调用、事件/hook、终止和视频输出引用；先以无视频 Player 实机直接 destroy 证明终态，再接 SDR PlatformView、两种 Texture、HDR/P5，详见本条 context。继续失败 disposal/global-ref 定量闭合、P5 双视图和属性序列中途故障；补连续可见帧与 mpv WID 回读，再决定提前停轨默认值。

- [ ] 排查 Android HDR 天空渐变层纹
  - status: deferred_by_user
  - context: archives/conversations/android-hdr-dv-display-plan-20260922.md
  - acceptance: 同 PTS 对照片源、解码/合成、输出位深和屏幕处理；若有可行改法，保持 HDR10/P8.4 的亮暗、颜色与全屏流畅性，再请用户人工确认。
  - latest: 最高亮度全屏验收中 HDR10 天空有层纹、P8.4 较轻，其余画面良好。按用户要求先记录，本轮不修；关闭抖动没有明确性能收益，也不是已验证的层纹修复。

- [ ] 排查 P5 Texture SDR 片尾紫色视频区域
  - status: queued
  - context: archives/conversations/android-hdr-dv-display-plan-20260922.md
  - acceptance: 同源重复到EOS，区分片源最后一帧、mpv end-file状态、Texture/Surface释放与Flutter呈现；片尾显示符合明确策略（保留末帧或清黑），重入无残影，HDR10/SDR回归正常。
  - latest: 12492指定Glass P5竖屏长播，媒体PTS174.874700秒的同进程日志直接报AImageReader `-30001`、硬解Surface映射失败和VO渲染失败；约1.14秒后的视频区域为纯RGB(128,0,255)，源末帧不是该色。隔离mpv源码的无效渲染分支恰用此紫色清空目标，但与现用JAR未重建到同字节；旧实验支持重复release同一Buffer为优先候选，12492缺身份与EOS证据，根因未定。见`archives/experiments/android-p5-glass-eos-purple-12492-20260927.md`。
  - tail_repro: 12526受控 `Media(start=170s)` 真全屏Texture短轮两独立进程：第一轮PTS174.958再现AImageReader `-30001`、渲染失败及整块紫色；第二轮尾部无第二次错误且保留视频末帧。两轮PTS170.003均有一次起播取图失败并恢复，不能与尾部混同。尚缺同刻end-file和codec buffer身份，根因未定。见`archives/experiments/android-p5-tail-repro-12526-20260927.md`。
  - failed_probe: 12527尝试在隔离AImageReader加最近16次map身份轨迹，但自建诊断包首次播放初始化即`info_callback`重复递归SIGSEGV，未进入尾段，不能作为紫屏根因证据；临时源码已恢复、失败JAR已删。见`archives/experiments/android-p5-tail-map-trace-12527-failed-20260927.md`。
  - next: 在尾段失败时输出最近map的reader代次、源帧/codec buffer身份、PTS、release与callback；先用尾段起播缩短复现，若不复现改为整片。确认同因后设计兼容延退的同帧所有权，并以完整Glass EOF、暂停重绘、seek及退出重入验证。
  - source_scope: 旧 Glass 片仍保留作为 PTS≈175 秒紫屏的定点复现素材；新的 Mystery Box P5 片时长约99秒，先用于正常 EOF 回归，不能代替旧片的故障复现。

## Blocked（等待输入或外部条件）

- [ ] 在真实 OHOS 设备上继续验证 native output 生命周期
  - status: blocked_waiting_for_device
  - context: archives/conversations/native-output-rebuild-20260920.md
  - acceptance: 原生输出实际呈现、后台/前台、退出/重入及 Surface 重建后持续播放且资源闭合；区分实体机、模拟器与静态检查证据。
  - latest: 2026-09-27 当前主机 `hdc list targets` 返回 `[Empty]`，没有可连接的真实 OHOS 设备；待设备接入后重新核验身份、包与运行状态，再继续实机验收。

## Closed（结案，未达原门槛）

- [x] 原统一素材范围（含Glass P5）首个可辨画面小于2秒：**未达成并结案；用户现改用P8.4另立上方验收项**。指定Glass P5片头约2.052秒黑场，保持从片头原速播放时仅素材时间即超过2秒；物理全屏受控读回可辨内容三轮3.543/3.374/3.625秒。SDR、HDR10 Texture→SDR、P8.4 Texture→SDR在已预建全屏路径的受控三轮均低于1秒；无同包关闭预建A/B，不能证明未经修改也达标或全部收益来自预建，亦不覆盖普通入口、光学触摸起点或原生HDR。预建通用入口及约1.41秒P5 A/B/A收益保留；详情与证据见`archives/experiments/android-first-visible-two-second-closure-20260927.md`。

## Recently Done（最近完成）

- [x] 复核 Android HDR10/DV 回退后 Release 卡顿观察；A/B/C 审查完成，日志开销仅是可能诱因。`archives/conversations/android-hdr-release-vs-debug-review-20260922.md`
- [x] 编译并安装 Android 实机 APK；构建/部署与播放验收分开。`archives/conversations/android-hdr-dv-display-plan-20260922.md`
- [x] 切换 OHOS libmpv 二进制发布来源至 Goodwu 20260920。`archives/conversations/ohos-libmpv-release-20260920.md`
- [x] 修复跨平台 native video output 重建与释放的已定义代码/提交门槛；真实设备长期生命周期由上方任务继续跟踪。`archives/conversations/native-output-rebuild-20260920.md`
- [x] 修复 macOS native output 首帧呈现与 epoch gating 的已定义代码/提交门槛。`archives/conversations/native-output-rebuild-20260920.md`
- [x] 清理本地工作树忽略项。`archives/conversations/native-output-rebuild-20260920.md`

## 规则

- 新任务写入本文件；活跃项保留 `context`、可验证的 `acceptance` 和当前 `latest/next`。
- 实验流水、包身份、日志和历史判断写入对应 conversation 或 experiments，不在任务项重复堆积。
- 完成项打勾并移入 Recently Done；超过近期容量后留存于 context/Git 历史。
- 提交前同步 TASKS 与/或对应 conversation；变更记录以 Git log 为准。
