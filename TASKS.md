# TASKS.md

任务事实源：这里只保留当前状态、验收门槛和下一步。2026-09-27 清理前的完整实验流水保存在 `archives/experiments/tasks-ledger-snapshot-20260927.md`；按各项 `context` 查看持续更新的依据。

## Now（当前推进，最多 3 条）

- [ ] Android HDR10 / DV P8.4 / P5 显示闭环
  - status: in_progress
  - context: archives/conversations/android-hdr-dv-display-plan-20260922.md
  - acceptance: 固定素材身份与设备能力；PlatformView 对 HDR10/P8.4/P5 分别输出 PQ/HLG/PQ，Texture 明确转换到 SDR；核对实际后端、Surface 格式、系统 HDR 合成、SDR 复位和全屏可见画面。P8.4 的无 HLG 路径、P5 DV 元数据处理及原生 DV 能力须单独说明，不能以 PQ 转换冒充原生 DV。最高亮度仅用于短时人工观察，每轮结束立即恢复原自动亮度，不长时间停留静态画面。
  - latest: HDR10、P8.4 已获用户真全屏画质/流畅性好评；10436/10437 P5 同页全屏画面良好，10437 的 SF/HWC 为 10 位 BT.2020/PQ，但依赖精确固件私有探针。此固件普通应用 GPU producer 的已试公开 PQ 出口均失败，11009 AHardwareBuffer 同样因 HDR 能力权限拒绝 SIGABRT。12464 正确 P5 JAR 短轮的 PQ Surface 拒绝且 `wid=0`，Dart 10 秒后超时；12465/12466 的失败 ACK 在拒绝后约 76/78 ms 报具体错误。12466 强制 GPU PQ 时 HDR10 也被拒绝；12468 P5 失败后同进程原生 `mediacodec_embed` HDR10/P8.4 依次恢复，SF/HWC 为 BT.2020/PQ(metadata types=3)/HLG(types=0)，两源各相隔3秒的视频区截图均变化。12471 再接 SDR 时视频层复位 BT.709、HDR metadata types=0，间隔3秒截图视频区域变化；仅覆盖原生 HDR 路径，见`archives/experiments/android-hdr-sdr-recovery-12471-20260927.md`。默认产品 P5 PQ、静态元数据、独立色准及全屏双视图一致性仍开放。
  - next: 原生 HDR→SDR 信令复位已有短轮证据；继续真全屏可见画面、GPU HDR→SDR Surface 复位及 P5 PQ 路径。停止此固件重复公开 PQ 探针。P5 Texture SDR 仅作明确标示的降级，不关闭 PQ 任务。

- [ ] P5 Glass 4K59.94 真全屏性能门槛
  - status: in_progress
  - context: archives/conversations/android-hdr-dv-display-plan-20260922.md
  - acceptance: 使用指定 Glass P5 源（SHA-256 `afb24b77733a3ca9071f0cfea0d0f7871670a7b6119eb44a314cba974541477c`）在原生屏幕尺寸、默认电池模式下真横屏播至 EOS；记录实际输出尺寸、每 30 秒 VO/decoder 掉帧、媒体时间、GPU 频率和温度，并以真人可见流畅度单独验收。性能模式和降低输出分辨率的结果不得替代默认配置门槛。
  - latest: 同 APK、2560×1440 输出的系统性能模式开/关/开 EOS VO 掉帧为 17/5051/19，decoder 为 0；默认模式门槛未过。1920×1080 也出现伴随 GPU 低频的后段失速；关闭抖动无明显低频收益，已停止该方向。用户最近确认 10437 的 1440 宽 P5 吹玻璃画面流畅，但这不覆盖 2560 默认模式全片门槛。
  - next: 在同一正式全屏路径、固定输出尺寸和默认电池模式下分离低频时的 GPU 渲染与提交/合成等待，再对有效改动做同帧颜色及全片 A/B/A 复核。

- [ ] 将手机视频打开到首个可见画面缩短至 2 秒内（争取 1 秒）
  - status: in_progress
  - context: archives/conversations/android-hdr-dv-display-plan-20260922.md
  - acceptance: 在真实手机上，以用户触发打开视频为起点、屏幕实际呈现首个视频帧为终点计时；覆盖当前支持的 SDR、HDR10、P8.4、P5 代表素材及冷/热启动，重复记录分布与最慢样本，正常播放达到 2 秒内，争取 1 秒内。视频尺寸或 Surface ACK 不能冒充实际出图；同时保持画质、音画同步、全屏及退出/重入正确。
  - latest: 12472 热页面 SDR 点击反馈→画面约133/100/100ms，但不含触摸到反馈。12479 同机五次冷 SDR 非黑截图上界1.48–1.56秒。用户指定 Glass P5：12480测试页整片哈希复制一次至内容上界16.695秒，准备占10.390秒；12481临时预验证直开三次6.283/5.981/6.640秒；12483显式GPU缓存目录无命中/收益证据。12485同一SurfaceProducer链设备时钟取样证明洋红转黑早于首个AImage，是初始化黑画面；首次非黑内容约4.30–4.55秒，片源黑场约2.052秒。12485同JAR VO短轮 media_opened→首个decoder release约1.01秒，release→ImageReader仅毫秒级。12489诊断性从3.5秒起播三次首次非黑约4.034/4.245/3.966秒；跳过黑场无明显达标收益。12493–12495同JAR四轮把Flutter Surface首次内容测为4.282–4.525秒，媒体位置到2.1秒后约0.30–0.36秒检出内容；80ms与20ms PixelCopy间隔区间重叠。位置通知曾早于首个AImage约0.95秒，不能当作呈现帧PTS。隔离构建已重链出与JAR逐字节相同的libmpv，但仍需历史AImageReader object。12496同包关→开→关的旧阈值内容时间4.490/4.385/4.975秒；开启轮实际PTS2.102帧已渲染并返回flip，但278ms后才超过旧PixelCopy阈值。12497逐次采样证实该阈值偏晚：首次非零像素约4.625秒，旧阈值在4.877秒；PTS2.102的flip至首个非零采样约132ms，仍含采样间隔与缓冲，不是纯显示耗时。三轮HEVC缺参考POC均复现，无因果结论。见`archives/experiments/android-p5-glass-media-clock-startup-12493-12495-20260927.md`、`archives/experiments/android-p5-jar-exact-baseline-20260927.md`、`archives/experiments/android-p5-glass-vo-mix-startup-12496-20260927.md`及`archives/experiments/android-p5-glass-precontent-12497-20260927.md`。
  - next: 真实布局驱动的SurfaceProducer预绑定已在12506单次P5前台打开跑通，继续做同包关/开回摆、冷/热分布、P5 RPU逐帧、同PTS画质、真全屏、退出/重入和实际4K输出；补后台恢复零wid回退与快速重挂载。正常无布局调用应明确降级。分开报告片源黑场、首个真实视频帧与首个非黑画面；以物理屏幕校准，并覆盖 SDR/HDR10/P8.4。原生同单调时钟探针继续确认硬解设备失败、软件解码、VO null与重配，不能把Dart异步MPVLOG或`stream.position`当呈现证据；外部预验证固定文件仅诊断用。显式缓存若再验证须先证明写入/命中并做空→热→空回摆。
  - diagnosis: 12497同进程`media_opened`→首个AImage约1.673秒；首个AImage后曾有两次空取图重试。12498同进程首开/重开各一轮：`media_opened→MediaCodec组件创建`约0.974/0.028秒，首开17行POC而重开无；两次OS/缓存状态不同，未证因果。重开PixelCopy首样本是旧画面，不能算新首帧；RPU属性0对照被测试入口拒绝。12499开启mpv详细日志后冷开总阶段几乎复现12498，消息顺序见硬解设备首次不可用→9线程软件HEVC/VO null→重新打开硬解/VO gpu-next；这提示启动解码器切换可能是前0.97秒的可优化点，但Dart异步MPVLOG时间戳不代表原生发生时间，旧POC/OMX行先后不能用作因果证据。见本条12497–12499实验归档。
  - presize_probe: 12500固定4K预建SurfaceProducer Surface并等非零wid/gpu-next后open，单轮首个AImage约0.735秒、固定区域首次非零3.003秒。12501同APK属性关→开→关首个AImage2.485/1.177/2.550秒，首次非零4.718/3.476/5.137秒，`media_opened→OMX创建`0.996/0.031/1.269秒；证据支持测试链里Surface未就绪导致软件→硬件重配约1秒。12502 1×1预建后mpv属性残留1×1，画面异常；12503页面尺寸1440×810预建后首次非黑3.859秒。12504补同步尺寸属性，1×1预建后读回4K且两轮首次非黑3.670/3.464秒、截图可辨认。12506由已挂载Video真实布局1440×810预建并严格绑定，首个AImage约0.795秒，首次非黑3.384秒，后续原生请求4K，截图可辨认；仅单轮竖屏测试页，未证明通用产品画质/RPU、全片或2秒目标。见对应12500–12506实验归档。

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
  - next: 核验清理中再次点击、失败重试和全屏组合。任意宿主直接 FlutterEngine.destroy 需先做独立于 Dart 的 Android 原生播放器 owner broker，统一 mpv 调用、事件/hook、终止和视频输出引用；先以无视频 Player 实机直接 destroy 证明终态，再接 SDR PlatformView、两种 Texture、HDR/P5，详见本条 context。继续失败 disposal/global-ref 定量闭合、P5 双视图和属性序列中途故障；补连续可见帧与 mpv WID 回读，再决定提前停轨默认值。

- [ ] P5 RPU 边界与独立色彩核验
  - status: queued
  - context: archives/conversations/android-hdr-dv-display-plan-20260922.md
  - acceptance: 对实际输出逐帧核对 RPU 对应关系，覆盖 seek/flush/重开；以明确的参考母版、目标空间和映射策略做同 PTS 数值比较，并把独立色彩结论与用户观感分开。
  - latest: 10440 前后跳共4次flush，实际输出 RPU 匹配2321/2321、errors0。10444/10445 的重建前后短轮亦全匹配。12486 使用指定 Glass 原片头，同一 Player/进程连续三次打开均完成轨道确认；前两次关闭时实际输出 RPU 分别518/518、596/596匹配，errors0、unconsumed0，第三段退出无 summary，见`archives/experiments/android-p5-glass-rpu-reopen-12486-20260927.md`。10442 探针失声源自全局日志路由；见本条 context。长期重开和独立色准仍待核验，后者有母版身份及映射差异。

- [ ] 排查 Android HDR 天空渐变层纹
  - status: queued
  - context: archives/conversations/android-hdr-dv-display-plan-20260922.md
  - acceptance: 同 PTS 对照片源、解码/合成、输出位深和屏幕处理；若有可行改法，保持 HDR10/P8.4 的亮暗、颜色与全屏流畅性，再请用户人工确认。
  - latest: 最高亮度全屏验收中 HDR10 天空有层纹、P8.4 较轻，其余画面良好。按用户要求先记录，本轮不修；关闭抖动没有明确性能收益，也不是已验证的层纹修复。

- [ ] 排查 P5 Texture SDR 片尾紫色视频区域
  - status: queued
  - context: archives/conversations/android-hdr-dv-display-plan-20260922.md
  - acceptance: 同源重复到EOS，区分片源最后一帧、mpv end-file状态、Texture/Surface释放与Flutter呈现；片尾显示符合明确策略（保留末帧或清黑），重入无残影，HDR10/SDR回归正常。
  - latest: 12492指定Glass P5竖屏长播，媒体PTS174.874700秒的同进程日志直接报AImageReader `-30001`、硬解Surface映射失败和VO渲染失败；约1.14秒后的视频区域为纯RGB(128,0,255)，源末帧不是该色。隔离mpv源码的无效渲染分支恰用此紫色清空目标，但与现用JAR未重建到同字节；旧实验支持重复release同一Buffer为优先候选，12492缺身份与EOS证据，根因未定。见`archives/experiments/android-p5-glass-eos-purple-12492-20260927.md`。
  - next: 在尾段失败时输出最近map的reader代次、源帧/codec buffer身份、PTS、release与callback；先用尾段起播缩短复现，若不复现改为整片。确认同因后设计兼容延退的同帧所有权，并以完整Glass EOF、暂停重绘、seek及退出重入验证。

- [ ] 在真实 OHOS 设备上继续验证 native output 生命周期
  - status: queued
  - context: archives/conversations/native-output-rebuild-20260920.md
  - acceptance: 原生输出实际呈现、后台/前台、退出/重入及 Surface 重建后持续播放且资源闭合；区分实体机、模拟器与静态检查证据。

## Blocked（等待输入或外部条件）

- （暂无；以上未完成项仍可继续推进）

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
