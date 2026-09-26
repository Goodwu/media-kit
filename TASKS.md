# TASKS.md

任务事实源：这里只保留当前状态、验收门槛和下一步。2026-09-27 清理前的完整实验流水保存在 `archives/experiments/tasks-ledger-snapshot-20260927.md`；按各项 `context` 查看持续更新的依据。

## Now（当前推进，最多 3 条）

- [ ] Android HDR10 / DV P8.4 / P5 显示闭环
  - status: in_progress
  - context: archives/conversations/android-hdr-dv-display-plan-20260922.md
  - acceptance: 固定素材身份与设备能力；PlatformView 对 HDR10/P8.4/P5 分别输出 PQ/HLG/PQ，Texture 明确转换到 SDR；核对实际后端、Surface 格式、系统 HDR 合成、SDR 复位和全屏可见画面。P8.4 的无 HLG 路径、P5 DV 元数据处理及原生 DV 能力须单独说明，不能以 PQ 转换冒充原生 DV。最高亮度仅用于短时人工观察，每轮结束立即恢复原自动亮度，不长时间停留静态画面。
  - latest: HDR10、P8.4 已在真横屏/最高亮度下获得用户的亮暗、颜色和流畅性好评；10436 P5 全片与 10437 4K59.94 吹玻璃源用同页全屏消除了旧页印记，用户均确认画面良好。10437 同包复播的 SF/HWC 回读为 10 位 BT.2020/PQ；10436 没有同轮 HWC 回读。LYA-AL00/API29 的 P5 PQ 仍依赖精确固件、属性门控的私有 ABI 探针，默认产品路径未通过；10439 公开 SurfaceControl PQ 色层实验因 HDR 能力查询权限拒绝而崩溃，代码已撤销。静态 HDR 元数据、独立色准、P5 通用输出及双视图一致性仍开放。
  - next: 从支持的公开输出机制或设备能力边界确定可交付的 P5 路径；在不依赖私有探针的包上复核实际 HDR/SDR 切换。保留已通过的同页全屏体验。

- [ ] P5 Glass 4K59.94 真全屏性能门槛
  - status: in_progress
  - context: archives/conversations/android-hdr-dv-display-plan-20260922.md
  - acceptance: 使用指定 Glass P5 源（SHA-256 `afb24b77733a3ca9071f0cfea0d0f7871670a7b6119eb44a314cba974541477c`）在原生屏幕尺寸、默认电池模式下真横屏播至 EOS；记录实际输出尺寸、每 30 秒 VO/decoder 掉帧、媒体时间、GPU 频率和温度，并以真人可见流畅度单独验收。性能模式和降低输出分辨率的结果不得替代默认配置门槛。
  - latest: 同 APK、2560×1440 输出的系统性能模式开/关/开 EOS VO 掉帧为 17/5051/19，decoder 为 0；默认模式门槛未过。1920×1080 也出现伴随 GPU 低频的后段失速；关闭抖动无明显低频收益，已停止该方向。用户最近确认 10437 的 1440 宽 P5 吹玻璃画面流畅，但这不覆盖 2560 默认模式全片门槛。
  - next: 在同一正式全屏路径、固定输出尺寸和默认电池模式下分离低频时的 GPU 渲染与提交/合成等待，再对有效改动做同帧颜色及全片 A/B/A 复核。

- [ ] 修复 macOS modern mpv 销毁时未释放 render context 的崩溃
  - status: in_progress
  - context: archives/conversations/native-output-rebuild-20260920.md
  - acceptance: 同一控制器的并发 dispose 共用完成屏障；Player 销毁前完成 native output/render context 释放，dispose 后不再写 active notifier。用 modern mpv 实际播放后退出、快速重入和输出重建，均无 `mpv_render_context_free() not called` abort。
  - latest: 新增 Darwin Player preTermination 释放屏障、创建/销毁仲裁及失败重试，V2 静态复审通过。隔离的 Goodwu mpv 0.41 W0 测试包实际播放 SDR：首个 native Surface 出图并释放，重建的第二个 Surface 再次出图，Player dispose 完成，进程未出现 render-context abort；见 `archives/experiments/macos-w0-modern-20260927.md`。应用 Quit 未打印第二个 Surface 的释放 ACK，不能据此判定完整退出合格。
  - next: 用真实 PiliPlusX modern mpv 验证有序退出、快速重入、seek、输出重建和 HDR 长播；取得第二个 Surface 与 render context 释放顺序后再关闭本项。

## Next（近期候选，最多 10 条）

- [ ] 将手机视频打开到首个可见画面缩短至 2 秒内（争取 1 秒）
  - status: queued
  - priority: 当前 Android HDR/P5 工作完成后立即启动，先于其它 Next 项
  - context: archives/conversations/android-hdr-dv-display-plan-20260922.md
  - acceptance: 在真实手机上，以用户触发打开视频为起点、屏幕实际呈现首个视频帧为终点计时；覆盖当前支持的 SDR、HDR10、P8.4、P5 代表素材及冷/热启动，重复记录分布与最慢样本，正常播放达到 2 秒内，争取 1 秒内。视频尺寸或 Surface ACK 不能冒充实际出图；同时保持画质、音画同步、全屏及退出/重入正确。
  - latest: 用户反馈目前从打开到出图较慢；尚无同一计时口径的实机基线，不能把此前约 6–11 秒的粗略观察当作当前版本数据。
  - next: 先建立真实首帧呈现信号与冷/热启动基线，再分解媒体打开、探测/解码、Surface 创建、GPU 首帧提交和系统呈现各阶段耗时，按最大瓶颈优化并复测。

- [ ] Android native output / 双视图生命周期回归
  - status: queued
  - context: archives/conversations/android-hdr-dv-display-plan-20260922.md
  - acceptance: Surface 重建、Home→前台、退出/重入、oldA→newB 交错和失败重试时，播放器位置与持续可见帧正确，资源最终释放；晚到 Create、Release ACK 丢失及 engine detach 有明确 owner/屏障，不以构建或单次 EOS 代替生命周期验收。
  - latest: P8.4 10447开/10448关/10449开双 Home→返回对照：提前停轨两轮POC0、无后台软解格式；关闭轮POC34，VO仍有掉帧。10450暂停后返回保持暂停；10451 HDR10双返回持续MediaCodec/PQ、POC0且系统PQ合成。稳定key双视图10453移除备用仍可见，10454移除当前后剩余B冻结。10455存活owner保留与回退候选在同场景中成功重绑B；补齐有界释放/绑定重试后，独立V1复审通过，10456实机正常路径再次恢复B且5秒截图变化。10457一次释放失败由重复destroy回调恢复；10458连续两次释放失败后由250ms定时重试恢复B；10459一次B绑定失败后由250ms定时重试恢复B，5秒截图均有画面变化。10460 HDR10 同序列 B 恢复持续出图，HWC PQ 合成。10461 普通 SDR 同序列 B 恢复持续出图、SF 无 HDR 元数据。见`archives/experiments/android-p84-dual-view-10453-10454-20260927.md`、`archives/experiments/android-p84-dual-view-10455-20260927.md`、`archives/experiments/android-p84-dual-view-10456-10457-20260927.md`、`archives/experiments/android-hdr10-dual-view-10460-20260927.md`、`archives/experiments/android-sdr-dual-view-10461-20260927.md`。提前停轨开关仍默认关闭。
  - next: 10461正常Android Back后engine先detach，Factory为原handle保留viewId 0/1/2且无PlayerTerminated证明；同进程重入可出图但旧owner回收未证实。10462根诊断页等待Player dispose后退出，同进程两轮返回/重入无保留告警；10463补共享Future后V1复审通过，自动停止与Back并发时退出确实等到Player销毁完成。见`archives/experiments/android-sdr-engine-detach-10461-20260927.md`及`archives/experiments/android-sdr-engine-exit-10462-20260927.md`。任意宿主直接FlutterEngine.destroy仍缺native生命周期仲裁，失败disposal重试和owner/global-ref定量计数未验；随后再验P5、oldA→newB交错及属性序列中途故障，最后决定提前停轨默认开启。

- [ ] P5 RPU 边界与独立色彩核验
  - status: queued
  - context: archives/conversations/android-hdr-dv-display-plan-20260922.md
  - acceptance: 对实际输出逐帧核对 RPU 对应关系，覆盖 seek/flush/重开；以明确的参考母版、目标空间和映射策略做同 PTS 数值比较，并把独立色彩结论与用户观感分开。
  - latest: 10440 前后跳共4次flush，实际输出 RPU 匹配2321/2321、errors0。10444 用临时 mpv 实例恢复日志后，重建前后实际输出206/206、227/227匹配。10445 用已修复的 mpv 日志接管且不需临时实例，前后201/201、225/225匹配、errors0，图像资源归零。10442 探针失声源自全局日志路由。见`archives/experiments/android-p5-rpu-seek-10440-20260927.md`、`archives/experiments/android-p5-rpu-rebind-10444-20260927.md`、`archives/experiments/android-mpv-ffmpeg-log-handoff-10445-20260927.md`。长期重开和独立色准仍待核验，后者有母版身份及映射差异。

- [ ] 排查 Android HDR 天空渐变层纹
  - status: queued
  - context: archives/conversations/android-hdr-dv-display-plan-20260922.md
  - acceptance: 同 PTS 对照片源、解码/合成、输出位深和屏幕处理；若有可行改法，保持 HDR10/P8.4 的亮暗、颜色与全屏流畅性，再请用户人工确认。
  - latest: 最高亮度全屏验收中 HDR10 天空有层纹、P8.4 较轻，其余画面良好。按用户要求先记录，本轮不修；关闭抖动没有明确性能收益，也不是已验证的层纹修复。

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
