# TASKS.md

任务事实源：这里只保留当前状态、验收门槛和下一步。2026-09-27 清理前的完整实验流水保存在 `archives/experiments/tasks-ledger-snapshot-20260927.md`；按各项 `context` 查看持续更新的依据。

## P5 当前优先级（2026-09-28）

P5→PQ 输出、首帧和性能使用 `/Users/wuweiwei1/Downloads/test-clips/Mystery Box Dolby Vision Profile 5.mp4`，SHA-256 `3e610d3b1b11e9b802da66d69bd97f6371a2b114ee464a7e8517fe31d706cc9f`；HEVC Main 10、3840×2160、60000/1001 fps、DV Profile 5/RPU、98.944 秒。用户确认片头无黑场。P5→Texture SDR 默认优化验收继续使用原 Glass P5 4K59.94（SHA-256 `afb24b77733a3ca9071f0cfea0d0f7871670a7b6119eb44a314cba974541477c`）与旧同片结果对照；按用户补充，Mystery Box 也另测一轮 Texture SDR 全片基准，后续同片复测。Glass 仍保留作片尾紫屏定点复现。

### P0 · P5→Texture SDR 优化默认开启并验证

- [x] status: done；最终版 Glass 短播获用户真人确认“画面良好，无异常”；context: archives/conversations/android-hdr-dv-display-plan-20260922.md
- acceptance: 在支持的 P5→Texture SDR 条件下默认启用通用 `optimize_dovi_linear_decode`，其他场景安全回退；自建 arm64 JAR 确认包含并命中优化。Glass 真横屏 2560×1440、默认电池模式全片到 EOS，画质、资源和真人观感正常，VO 与既有优化轮 EOS 516、t90→t180 新增342相近即可，不再追逐旧严格门槛。Mystery Box 同配置复测，与自身未优化基准比较，记录 GPU 频率。
- latest: 旧 Glass 同配置诊断 A/B/A 的 Texture SDR EOS VO 为2607/516/3626；Mystery Box 未优化全片 VO54、decoder0，GPU中位586MHz。FFmpeg `fff3ee7`、libplacebo `c9fd879` 已推送Goodwu fork。mpv `aa8bd10`修同帧复用、`91554aa`修普通 OES 回退、`33a212e`删可选缓存与高频日志，均已推送。12569真正 `gpu-next`/`mediacodec`、2560×1440 Mystery Box 全片 EOS VO2、decoder0、GPU中位415MHz、AImage5928/5928；12570 Glass 全片 EOS VO41、decoder0、GPU中位415MHz、AImage10433/10433、片尾正常。12567普通 SDR、12571 HDR10、12572 P8.4 同版短轮均实际出画且资源对齐（后两者仅 Texture→SDR 回退）。12573 清理版 Mystery Box 短轮 t8 VO3、decoder0、AImage1513/1513。最新隔离 mpv 再删原始 YUV FBO/MRT/PACK10、sidecar 和读回探针，arm64 编译及独立审查通过；12574 Mystery Box 短轮实画、AImage1483/1483；12575 Mystery Box 全片完成，t90 VO34、decoder0、GPU104样本中位415MHz、AImage5886/5886；12576 Glass 全片完成，t180 VO22、decoder0、片尾截图正常、AImage10454/10454，但 PTS174.958 仍有一次 AImageReader 无图像/渲染失败，属 P3 尾段故障。12576主机空间满使GPU只采37秒，且两条全片均未取得精确 EOS VO 快照。见 `archives/experiments/android-p5-product-raw-prune-12574-12576-20260928.md` 及前述各版本实验记录。
- latest_acceptance: 2026-09-28 最终12585 Glass短播复看，用户报告“画面良好，无异常”；t28 VO4/decoder0，无取图/渲染错误。恢复12492、自动亮度、熄屏。全片和回退证据见 `archives/experiments/android-p5-glass-default-12581-12585-20260928.md`、`archives/experiments/android-p5-mystery-default-12586-20260928.md`；片尾偶发故障仍属P3。

### P1 · P5→PQ 公开产品输出与首帧

- [ ] status: in_progress；context: archives/conversations/android-hdr-dv-display-plan-20260922.md
- acceptance: 以 Mystery Box 从正常入口横屏全屏出真实画面，确认 `gpu-next`/`mediacodec`、10 位 BT.2020/PQ 视频层、系统 HDR 合成和退出后 SDR 复位；核清 HDR 静态元数据的来源与缺失边界，片源没有的母版值不可伪造。触摸到可辨内容小于2秒、争取1秒，探针绑定当前 View/Surface 代次，并以真人观察佐证。公开 Android 输出链路优先；精确固件私有探针仅在公开方案确实不可行时作为受限备选。
- latest: 12542–12544 精确固件私有探针得到 PQ 实际画面及系统合成，但不是产品链路；12539 公开 Surface PQ 设置失败，`wid=0`。旧 Glass 片头黑场使12543/12544约4秒可辨内容读回不能作为新片首帧结论；12544探针仍未绑定实际 Surface generation。只读复核确认本固件公开NDK setter受SF权限/能力门禁阻断，EGL/Vulkan没有可用PQ Surface协商，公开SurfaceControl PQ事务SIGABRT；API29 ImageWriter未提供可用的公开PQ dataspace出口。没有值得原样重试的公开GPU PQ路径，但不推广为Android整体不支持。隔离产品候选已收紧为公开 setter 返回-22、精确固件/格式才回退，持续PQ监测与运行中失败stop→release→ACK；arm64 12582 APK构建成功、只含arm64库，修订协议独立静态复审无新增阻断，尚未安装/出画/故障注入。见 `archives/experiments/android-p5-private-pq-probe-target-12544-20260928.md`、`archives/experiments/android-p5-public-pq-route-assessment-20260928.md`、`archives/experiments/android-p5-pq-product-candidate-12582-20260928.md`。
- latest_device: 12582首次正常入口 Mystery Box 短轮：8/20秒截图为不同实际画面；当前View generation2采用RGBA1010102，公开setter -22 后精确固件回退成功，SF与HWC均为BT.2020/PQ、10位DEVICE合成。SF HDR静态元数据类型0；片源ffprobe仅有DOVI配置side data。FirstFramePixelCopy误选旧Surface而零有效样本，首帧尚无时间结论。见 `archives/experiments/android-p5-pq-product-candidate-12582-20260928.md`。
- latest_followup: 12589首帧探针绑定实际PQ View，三独立轮触摸按下→Surface可辨内容1.144/1.214/1.057秒，非面板光学计时；12591修复PQ→SDR时的旧PQ Surface残留，12594无注入回归PQ首图1.084秒并自动切SDR出画。12593受控PQ失效注入验证停解码、AImage闭合、ReleaseSurface/ACK及失效层隐藏；12595首轮ACK失败后重试成功，12597旧PQ层释放五秒后故障事件到达，新SDR层仍继续显示。诊断注入均已从正式代码撤销。12598无注入正常PQ横屏长播，触摸→当前Surface可辨内容1.090秒，SF/HWC为BT.2020/PQ、10位视频层；用户在同步重播中确认“画面良好，无异常”。V1独立复核无确定性代码阻断。见同一P1实验记录。
- next: 核验实际运行中PQ失效后的同进程重试；以最终无注入代码复核PQ→SDR复位和连续出画，然后合入产品候选。P1未验收前不转P2。

### P2 · P5→PQ 全片性能

- [ ] status: queued_after_P1；context: archives/conversations/android-hdr-dv-display-plan-20260922.md
- acceptance: Mystery Box 在正式 PQ 输出链路、默认电池模式和明确尺寸下播至 EOS；逐段记录 VO/decoder 掉帧、GPU 频率、温度和持续可见画面，必要时定向优化并同包 A/B 验证。
- latest: 12542–12544 的 PQ 短轮自建 JAR 未包含线性解码候选，尚无 PQ 全片掉帧数据；Texture SDR 的收益不能外推至 PQ。
- next: P1 产品路径稳定后测基线；复用 P0 的 RPU/线性解码及回退代码前，先核 PQ 目标真实命中、同 PTS 颜色，再量化性能收益。

### P3 · P5 生命周期及片尾故障

- [ ] status: queued；context: archives/conversations/android-hdr-dv-display-plan-20260922.md
- acceptance: 退出重入、Surface/双视图切换、失败重试、直接 Engine 销毁后资源正确释放且持续出帧；旧 Glass 片尾紫屏根因查明并修复，完整 EOF、暂停重绘、seek 与重入无残影；Mystery Box 用于正常 EOF 回归。
- latest: 12492 P5 播至 PTS164.8 后退出重入成功，直接 Engine.destroy 仍未验。Glass 尾段 PTS约175 曾有 AImageReader `-30001`、渲染失败及紫屏；12526 两轮中一轮复现、一轮保留末帧，缺 end-file 与 buffer 身份，根因未定。清理版12576在片尾PTS174.958再次出现一次同类取图/渲染失败，但片尾截图正常、播放完成；12580在Mystery Box seek开始的旧PTS8.008也出现一次，之后45秒处继续播放并同播放器重开成功、资源闭合。12585 Glass属性0全片在PTS174.991再次出现相同取图/渲染失败，随后EOS及资源闭合；仍不能判定紫屏根因。见 `archives/experiments/android-p5-tail-repro-12526-20260927.md`、`archives/experiments/android-p5-product-seek-reopen-12580-20260928.md`、`archives/experiments/android-p5-glass-default-12581-12585-20260928.md`。
- next: 按当前 owner/代次追踪退出与 Surface 交错；尾段短轮记录 reader、codec buffer、PTS、release 与 callback 身份，确认同因后修复并完成 Glass EOF 回归。

### P4 · 独立色彩数值验收

- [ ] status: queued_low_priority；context: archives/conversations/android-hdr-dv-display-plan-20260922.md
- acceptance: 对实际 P5 输出逐帧核对 RPU，覆盖 seek/flush/重开；明确参考母版、目标空间和映射策略，做同 PTS 独立数值比较。
- latest: 用户人工观察认为 P5 颜色基本正常；10440 seek/flush 匹配2321/2321，12512 两次重开匹配626/626与622/622、errors0/unconsumed0，但独立色准未完成。见 `archives/experiments/android-p5-glass-prebind-rpu-12512-20260927.md`。
- next: P0–P3 后补长期重开、当前布局 seek/flush 与独立色准。

## 其他当前任务

- [ ] Android HDR10 / DV P8.4 显示与原生 HDR 首帧闭环
  - status: in_progress
  - context: archives/conversations/android-hdr-dv-display-plan-20260922.md
  - acceptance: 固定素材和设备能力，核对 HDR10 PQ、P8.4 HLG 的真实后端、Surface 格式、系统合成、连续全屏画面及 SDR 复位；P8.4 无 HLG 路径与原生 DV 能力单独说明。原生 HDR 从触摸到视频内容小于2秒、争取1秒，补冷/热、重入与输出切换。最高亮度只用于短时人工观察，结束立即恢复自动亮度并熄屏。
  - latest: HDR10、P8.4 全屏画质和流畅性已获用户认可；12537 P8.4 HLG 三轮触摸按下→Surface 内容0.670/0.676/0.623秒，12538 HDR10 PQ 为0.653/0.648/0.630秒，视频层分别为 BT.2020 HLG/PQ。P8.4 Texture→SDR 普通入口人工验收通过：轻微偏淡可接受、流畅、声画同步，用户感受约1秒内出画，同轮读回0.844秒。读回还不是面板光学时间。见 `archives/experiments/android-native-hdr-firstframe-12537-12539-20260927.md`、`archives/experiments/android-p84-sdr-human-acceptance-20260927.md`。
  - next: 扩充原生 HDR 冷/热、重入、连续帧及 SDR 复位证据；P5 输出和首帧单列于 P1，不以 HDR10/P8.4 代替。

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
  - latest: P8.4/HDR10/SDR 的 Home→返回、双视图存活 B 回退、释放/绑定失败重试已有实机可见画面证据。12473/12474/12475受控SDR交错核验旧A的Available/Destroy晚到与ACK回复超时；12477旧A Failed注入后B成功出HDR10画面。12486 P5长播后重入在Flutter SurfaceTexture finalizer release栈出现一次SIGSEGV，归因未明。测试页自动单播放器 Back 现等待输出/Player清理；最终包12492 P5推进至媒体PTS164.8秒、早晚截图均有不同实际画面，Back时输出/Player完成早于Activity退出，同一PID重入再次出图且无SIGSEGV；未播及短播返回亦正确，V1复审无阻断，见`archives/experiments/android-auto-player-exit-12491-12492-20260927.md`。P5专属退出重入、直接Engine.destroy与片尾紫屏归入上方P3；通用Engine owner仍未验。注入均已撤销，提前停轨仍默认关闭；完整历史见本条 context。
  - p84_scope_exit: 12534暴露测试页普通Texture SDR退出时错误要求HDR清理报告，12535修正后同PID完成全屏→返回→播放页清理→主菜单→新页再出图。清理约5.1秒已定位到NativePlayer.dispose中刻意等待的5秒终止宽限期，非本轮新卡顿；保持既有终止屏障。见`archives/experiments/android-p84-touchdown-and-reentry-12533-12535-20260927.md`。
  - next: 核验清理中再次点击、失败重试和全屏组合。任意宿主直接 FlutterEngine.destroy 需先做独立于 Dart 的 Android 原生播放器 owner broker，统一 mpv 调用、事件/hook、终止和视频输出引用；先以无视频 Player 实机直接 destroy 证明终态，再接 SDR PlatformView、两种 Texture、HDR/P5，详见本条 context。继续通用失败 disposal/global-ref 定量闭合、连续可见帧与 mpv WID 回读，再决定提前停轨默认值；P5 专属双视图与属性序列故障归入 P3。

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
