# TASKS.md

任务事实源：这里只保留当前状态、验收门槛和下一步。2026-09-27 清理前的完整实验流水保存在 `archives/experiments/tasks-ledger-snapshot-20260927.md`；按各项 `context` 查看持续更新的依据。

## Now（当前推进，最多 3 条）

- [ ] Android HDR10 / DV P8.4 / P5 显示闭环
  - status: in_progress
  - context: archives/conversations/android-hdr-dv-display-plan-20260922.md
  - acceptance: 固定素材身份与设备能力；PlatformView 对 HDR10/P8.4/P5 分别输出 PQ/HLG/PQ，Texture 明确转换到 SDR；核对实际后端、Surface 格式、系统 HDR 合成、SDR 复位和全屏可见画面。P8.4 的无 HLG 路径、P5 DV 元数据处理及原生 DV 能力须单独说明，不能以 PQ 转换冒充原生 DV。最高亮度仅用于短时人工观察，每轮结束立即恢复原自动亮度，不长时间停留静态画面。
  - latest: HDR10、P8.4 已获用户真全屏画质/流畅性好评；10436/10437 P5 同页全屏画面良好，10437 的 SF/HWC 为 10 位 BT.2020/PQ，但依赖精确固件私有探针。此固件普通应用 GPU producer 的已试公开 PQ 出口均失败，11009 AHardwareBuffer 同样因 HDR 能力权限拒绝 SIGABRT。12464 正确 P5 JAR 短轮的 PQ Surface 拒绝且 `wid=0`，Dart 10 秒后超时；12465/12466 的失败 ACK 在拒绝后约 76/78 ms 报具体错误。12466 强制 GPU PQ 时 HDR10 也被拒绝；12468 P5 失败后同进程原生 `mediacodec_embed` HDR10/P8.4 依次恢复，SF/HWC 为 BT.2020/PQ(metadata types=3)/HLG(types=0)，两源各相隔3秒的视频区截图均变化。12471 再接 SDR 时视频层复位 BT.709、HDR metadata types=0，间隔3秒截图视频区域变化；仅覆盖原生 HDR 路径，见`archives/experiments/android-hdr-sdr-recovery-12471-20260927.md`。默认产品 P5 PQ、静态元数据、独立色准及全屏双视图一致性仍开放。
  - P5_RPU_color_gate: 对实际输出逐帧核对RPU与画面，覆盖seek/flush/重开；以明确参考母版、目标空间和映射策略做同PTS独立数值色彩比较，并与用户观感分开。10440前后跳4次flush匹配2321/2321；12512预建路径两次重开匹配626/626、622/622，errors0/unconsumed0。长期重开、该布局seek/flush和独立色准仍开放，见`archives/experiments/android-p5-glass-rpu-reopen-12486-20260927.md`、`archives/experiments/android-p5-glass-prebind-rpu-12512-20260927.md`。
  - next: 原生 HDR→SDR 信令复位已有短轮证据；继续真全屏可见画面、GPU HDR→SDR Surface 复位及 P5 PQ 路径，同时完成上方RPU/色准子门槛。停止此固件重复公开 PQ 探针。P5 Texture SDR 仅作明确标示的降级，不关闭 PQ 任务。

- [ ] P5 Glass 4K59.94 真全屏性能门槛
  - status: in_progress
  - context: archives/conversations/android-hdr-dv-display-plan-20260922.md
  - acceptance: 使用指定 Glass P5 源（SHA-256 `afb24b77733a3ca9071f0cfea0d0f7871670a7b6119eb44a314cba974541477c`）在原生屏幕尺寸、默认电池模式下真横屏播至 EOS；记录实际输出尺寸、每 30 秒 VO/decoder 掉帧、媒体时间、GPU 频率和温度，并以真人可见流畅度单独验收。性能模式和降低输出分辨率的结果不得替代默认配置门槛。
  - latest: 同 APK、2560×1440 输出的系统性能模式开/关/开 EOS VO 掉帧为 17/5051/19，decoder 为 0；默认模式门槛未过。1920×1080 也出现伴随 GPU 低频的后段失速；关闭抖动无明显低频收益，已停止该方向。用户最近确认 10437 的 1440 宽 P5 吹玻璃画面流畅，但这不覆盖 2560 默认模式全片门槛。
  - next: 在同一正式全屏路径、固定输出尺寸和默认电池模式下分离低频时的 GPU 渲染与提交/合成等待，再对有效改动做同帧颜色及全片 A/B/A 复核。

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
  - latest_hdr: 12537 P8.4原生HLG三独立进程触摸按下→视频Surface读回内容0.670/0.676/0.623秒；12538 HDR10原生PQ为0.653/0.648/0.630秒。各有真横屏全屏截图，SF视频层分别BT.2020 HLG(types0)/PQ(types3)。12539 P5自身转PQ在当前固件公开Surface设置被拒，`wid=0`，请求→明确失败0.422秒、无首帧。视频Surface读回可作为自动化时延门槛，但不能单独证明系统合成或面板显示，须配合同层SF/HWC、全屏画面及真人观察。见`archives/experiments/android-native-hdr-firstframe-12537-12539-20260927.md`。
  - next: 扩充原生HDR冷/热及同进程重入、连续画面和输出切换统计；维持P5 PQ未通过状态，待有受支持的PQ出口或其它设备再验真实首帧。保留面板光学与独立色度仪测量为精度限制。

## Next（近期候选，最多 10 条）

- [ ] 修复 macOS modern mpv 销毁时未释放 render context 的崩溃
  - status: queued
  - context: archives/conversations/native-output-rebuild-20260920.md
  - acceptance: 同一控制器的并发 dispose 共用完成屏障；Player 销毁前完成 native output/render context 释放，dispose 后不再写 active notifier。用 modern mpv 实际播放后退出、快速重入和输出重建，均无 `mpv_render_context_free() not called` abort。
  - latest: Darwin Player preTermination 屏障、创建/销毁仲裁及失败重试已通过 V2 静态复审。隔离 Goodwu mpv 0.41 W0 测试包完成 SDR 出图→重建→第二次出图→定时移除：两个 Surface 均有释放记录，两次 Player dispose 完成，进程未见 render-context abort，见 `archives/experiments/macos-w0-remove-20260927.md`。PiliPlusX 当前 Debug 和未改动 final16 包在此桌面环境均无可操作窗口，产品调用链仍未验收。
  - next: 定位 PiliPlusX 窗口不可访问的环境/应用状态，再验证产品调用链有序退出、快速重入、seek、输出重建及 HDR 长播；测试页的定时移除证据不能替代这些场景。

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
