# TASKS.md

任务事实源：这里只保留当前状态、验收门槛和下一步。2026-09-27 清理前的完整实验流水保存在 `archives/experiments/tasks-ledger-snapshot-20260927.md`；按各项 `context` 查看持续更新的依据。

## 接手快照（2026-09-30 更新；换 agent 从这里开始）

- **事实源与范围**：本文件是任务状态，`archives/README.md` 是主题导航，`archives/conversations/android-hdr-dv-display-plan-20260922.md` 顶部 `Current State` 是当前 Android 主题上下文；`archives/experiments/android-private-tmp-handoff-20260928.md` 是临时工作树路径及补丁入口。以上均为快照，接手后先重新读 Git/设备状态。
- **代码状态（2026-09-30 分支归一完成后）**：当前目录分支 `main`（f557834c，与远端同步，fork 仅剩此一分支）。P0–P5 全部 done。**三仓库单线格局**：① Goodwu/media-kit `main` = 原 `fix/darwin-video-output-rebuild-barrier` 全部工作 + 上游 main 236 提交合并（`a886f556`，63 冲突分层裁定，五项实机验收通过，证据 `archives/experiments/android-media-kit-main-merge-acceptance-12700-20260930.md`）；② Goodwu/mpv `media-kit/android`（tip `6719532` = 398d0c3 + av_log 接管 cherry-pick + 注释更正），发布基线 tag `media-kit-v2026.09`→`398d0c3`；③ FFmpeg `feature/android-mediacodec-p5-rpu`（`fff3ee7`）、libplacebo `optimize/dovi-linear-decode`（`c9fd879`）各单分支。**发布链**：mpv `398d0c3` + FFmpeg `fff3ee7` + libplacebo `c9fd879`，对应 JAR SHA-256 `dad30ae23cd75e85c43663959ce9e1c5940ae632adda404fbfe71d4202c2a9f7`（`/tmp/media-kit-p5-colorfix-398d0c3-arm64.jar`）。废弃分支均以 `archive/*-202609` tag 归档（mpv 实验线、media-kit piliplusx 集成线/Predidit 源快照等，全清单见 `archives/experiments/android-mpv-fork-branch-consolidation-20260930.md` 追加节）。
- **mpv fork 上游策略（2026-09-30 定）**：**跟发布版不跟 master**。基点 `32a164cc01` 即 v0.41.0 后不久的 master 快照（与 v0.41.0 仅差 vo_gpu_next 15 行），master 已领先 982 提交且其中 vo_gpu_next 1029 行是 libplacebo v7 API 迁移（与我们 1100+ 行改动正面冲突）、aimagereader 44 行为错误处理改进。**已核实 master 未包含我们任何一项修复**（dovi 重标定/直接采样/片尾回退/av_log 接管均无对应物）；maxImages 5→3 双方各自独立改过（同步时自动消解）。下次同步：等 v0.42 发布 → merge-tree 试评估（重点 hwdec API 与 vo_gpu_next dovi 路径）→ P5 五项回归后打新发布 tag；期间个别修复按需 cherry-pick（候选：上游 `14f2d48cbc` aimagereader 错误处理，与片尾回退互补）；FFmpeg 安全修复走 CVE 按需 cherry-pick 单独机制。**注意**：`media-kit/android` tip 的 av_log 修复尚未进产品 JAR（dad30ae2 基于 398d0c3 构建），下个发布周期重建 JAR 时纳入。
- **P5 修复要点**：~~华为硬解输出 8-bit NV12（AHB 0x325），GLES 外部 YUV 采样按 code/255~~（**更正 2026-09-30**：0x325 实为 Main10 10-bit 布局、驱动 Y2Y 采样器按 /1020 归一化；copy 路径 8-bit 是 ByteBuffer 另一输出模式不可外推——见 `archives/experiments/android-p5-buffer-bitdepth-mystery-20260930.md`），dovi 域按 code/1023 → 1023/1020 缩放偏色；修复为 dovi 元数据就地重标定（等价于恢复 9/25 sidecar 的 code_scale=1020/1023），数值验收 (47,50,70)/(50,19,58)/65535 ≤100。读回装置教训：旧前缀 FFmpeg 需 `debug.media_kit.p5_rpu_probe=2`；产品链接必须用 fff3ee7 世代 libavcodec（`/tmp/media-kit-p5-product-ffmpeg-lib/`），误链 mkp4prefix 旧版会复演 `direct=0`。详见 P5 条目与 `archives/experiments/android-p5-mediacodec-color-fix-20260930.md`。
- **环境**：ADB 可用（设备 `3EP7N18C28016072` / LYA-AL00），每轮结束恢复原 12492、自动亮度、熄屏。读回构建链：`/tmp/mkmpvsrc`（mpv fork 工作树，**现处 `media-kit/android` 分支 tip `6719532`**，产品构建用发布 tag `media-kit-v2026.09`=398d0c3）+ `/tmp/mkp4prefix` + 手工链接需补 `-lc++_shared`（build.ninja 行 1229/1230 提取）；APK 直改重签（lib store + zipalign -p 4096 + debug keystore + NDK 27.2 libc++_shared.so 同步替换）。JDK17（`/opt/homebrew/opt/openjdk@17`）构建、`ORG_GRADLE_PROJECT_mediaKitLocalArm64Jar` 注入 JAR 的正式流程不变；media-kit 主仓推送遇挂起时绕过 osxkeychain：`git -c credential.helper= -c credential.helper='!gh auth git-credential' push …`。合并验收轮脚本与像素判定留存 `/tmp/merge-accept-round.sh`、`/tmp/merge-accept-destroy-round.sh`、`/tmp/pixel-judge.py`。

## P5 当前优先级（2026-09-28）

P5→PQ 输出、首帧和性能使用 `/Users/wuweiwei1/Downloads/test-clips/Mystery Box Dolby Vision Profile 5.mp4`，SHA-256 `3e610d3b1b11e9b802da66d69bd97f6371a2b114ee464a7e8517fe31d706cc9f`；HEVC Main 10、3840×2160、60000/1001 fps、DV Profile 5/RPU、98.944 秒。用户确认片头无黑场。P5→Texture SDR 默认优化验收继续使用原 Glass P5 4K59.94（SHA-256 `afb24b77733a3ca9071f0cfea0d0f7871670a7b6119eb44a314cba974541477c`）与旧同片结果对照；按用户补充，Mystery Box 也另测一轮 Texture SDR 全片基准，后续同片复测。Glass 仍保留作片尾紫屏定点复现。

### P0 · P5→Texture SDR 优化默认开启并验证

- [x] status: done；最终版 Glass 短播获用户真人确认“画面良好，无异常”；context: archives/conversations/android-hdr-dv-display-plan-20260922.md
- acceptance: 在支持的 P5→Texture SDR 条件下默认启用通用 `optimize_dovi_linear_decode`，其他场景安全回退；自建 arm64 JAR 确认包含并命中优化。Glass 真横屏 2560×1440、默认电池模式全片到 EOS，画质、资源和真人观感正常，VO 与既有优化轮 EOS 516、t90→t180 新增342相近即可，不再追逐旧严格门槛。Mystery Box 同配置复测，与自身未优化基准比较，记录 GPU 频率。
- latest: 旧 Glass 同配置诊断 A/B/A 的 Texture SDR EOS VO 为2607/516/3626；Mystery Box 未优化全片 VO54、decoder0，GPU中位586MHz。FFmpeg `fff3ee7`、libplacebo `c9fd879` 已推送Goodwu fork。mpv `aa8bd10`修同帧复用、`91554aa`修普通 OES 回退、`33a212e`删可选缓存与高频日志，均已推送。12569真正 `gpu-next`/`mediacodec`、2560×1440 Mystery Box 全片 EOS VO2、decoder0、GPU中位415MHz、AImage5928/5928；12570 Glass 全片 EOS VO41、decoder0、GPU中位415MHz、AImage10433/10433、片尾正常。12567普通 SDR、12571 HDR10、12572 P8.4 同版短轮均实际出画且资源对齐（后两者仅 Texture→SDR 回退）。12573 清理版 Mystery Box 短轮 t8 VO3、decoder0、AImage1513/1513。最新隔离 mpv 再删原始 YUV FBO/MRT/PACK10、sidecar 和读回探针，arm64 编译及独立审查通过；12574 Mystery Box 短轮实画、AImage1483/1483；12575 Mystery Box 全片完成，t90 VO34、decoder0、GPU104样本中位415MHz、AImage5886/5886；12576 Glass 全片完成，t180 VO22、decoder0、片尾截图正常、AImage10454/10454，但 PTS174.958 仍有一次 AImageReader 无图像/渲染失败，属 P3 尾段故障。12576主机空间满使GPU只采37秒，且两条全片均未取得精确 EOS VO 快照。见 `archives/experiments/android-p5-product-raw-prune-12574-12576-20260928.md` 及前述各版本实验记录。
- latest_acceptance: 2026-09-28 最终12585 Glass短播复看，用户报告“画面良好，无异常”；t28 VO4/decoder0，无取图/渲染错误。恢复12492、自动亮度、熄屏。全片和回退证据见 `archives/experiments/android-p5-glass-default-12581-12585-20260928.md`、`archives/experiments/android-p5-mystery-default-12586-20260928.md`；片尾偶发故障仍属P3。
- temp_reconcile: 已静态核对旧 `media-kit-p5-libplacebo` 唯一源码差异为P5优化命中等诊断日志和局部变量初始化；正式 `c9fd879` 已有优化实现。P0正式Glass/Mystery Box全片、非P5回退及真人观感已覆盖产品链路，旧工作树于2026-09-29删除，源码补丁留存。旧 `media-kit-p5-mpv` 的P5自动YUV/退休和downscaler设置也已由正式产品包含，P0回归后同日删除，补丁留存。`media-kit-ffmpeg-n713-clean` 的 `libavformat/hls.c` 修改及21个 `_build-release-arm64` 生成项仍待比对。

### P1 · P5→PQ 公开产品输出与首帧

- [x] status: done；context: archives/conversations/android-hdr-dv-display-plan-20260922.md
- acceptance: 以 Mystery Box 从正常入口横屏全屏出真实画面，确认 `gpu-next`/`mediacodec`、10 位 BT.2020/PQ 视频层、系统 HDR 合成和退出后 SDR 复位；核清 HDR 静态元数据的来源与缺失边界，片源没有的母版值不可伪造。触摸到可辨内容小于2秒、争取1秒，探针绑定当前 View/Surface 代次，并以真人观察佐证。公开 Android 输出链路优先；精确固件私有探针仅在公开方案确实不可行时作为受限备选。
- latest: 12542–12544 精确固件私有探针得到 PQ 实际画面及系统合成，但不是产品链路；12539 公开 Surface PQ 设置失败，`wid=0`。旧 Glass 片头黑场使12543/12544约4秒可辨内容读回不能作为新片首帧结论；12544探针仍未绑定实际 Surface generation。只读复核确认本固件公开NDK setter受SF权限/能力门禁阻断，EGL/Vulkan没有可用PQ Surface协商，公开SurfaceControl PQ事务SIGABRT；API29 ImageWriter未提供可用的公开PQ dataspace出口。没有值得原样重试的公开GPU PQ路径，但不推广为Android整体不支持。隔离产品候选已收紧为公开 setter 返回-22、精确固件/格式才回退，持续PQ监测与运行中失败stop→release→ACK；arm64 12582 APK构建成功、只含arm64库，修订协议独立静态复审无新增阻断，尚未安装/出画/故障注入。见 `archives/experiments/android-p5-private-pq-probe-target-12544-20260928.md`、`archives/experiments/android-p5-public-pq-route-assessment-20260928.md`、`archives/experiments/android-p5-pq-product-candidate-12582-20260928.md`。
- latest_device: 12582首次正常入口 Mystery Box 短轮：8/20秒截图为不同实际画面；当前View generation2采用RGBA1010102，公开setter -22 后精确固件回退成功，SF与HWC均为BT.2020/PQ、10位DEVICE合成。SF HDR静态元数据类型0；片源ffprobe仅有DOVI配置side data。FirstFramePixelCopy误选旧Surface而零有效样本，首帧尚无时间结论。见 `archives/experiments/android-p5-pq-product-candidate-12582-20260928.md`。
- latest_followup: 12589首帧探针绑定实际PQ View，三独立轮触摸按下→Surface可辨内容1.144/1.214/1.057秒，非面板光学计时；12591修复PQ→SDR时的旧PQ Surface残留，12594无注入回归PQ首图1.084秒并自动切SDR出画。12593受控PQ失效注入验证停解码、AImage闭合、ReleaseSurface/ACK及失效层隐藏；12595首轮ACK失败后重试成功，12597旧PQ层释放五秒后故障事件到达，新SDR层仍继续显示。诊断注入均已从正式代码撤销。12598无注入正常PQ横屏长播，触摸→当前Surface可辨内容1.090秒，SF/HWC为BT.2020/PQ、10位视频层；用户在同步重播中确认“画面良好，无异常”。V1独立复核无确定性代码阻断。见同一P1实验记录。
- retry_followup: 12599以无注入产品代码复核PQ→SDR：PQ首图1.113秒，SDR BT.709/BT.1886继续出画，SF无旧PQ层。12600受控运行中失效后同路重试发现通用输出槽复用失败控制器；12601通用输出槽改为显式重试先走dispose屏障再建新控制器，同故障注入下第二次PQ出画、SF/HWC为新10位PQ层。注入已撤销；见P1实验记录。
- final_acceptance: 12601受控一次运行中PQ失效后同PID显式同路重试，新Surface继续出画且SF/HWC恢复10位PQ；独立V1复核无阻断。12602删除注入后的最终代码触摸→PQ可辨内容1.168秒，自动切SDR后实际画面、BT.709/BT.1886、无PQ旧层；12598同代码主路径获用户真人确认“画面良好，无异常”。首帧数字仍是当前Surface PixelCopy而非面板光学；P5源没有HDR10静态母版字段，SF types=0，不编造。正式实现保存在独立产品分支，PQ全片性能转P2。
- next: 进入P2 Mystery Box 正式PQ全片到EOS，记录掉帧、GPU频率、温度并决定是否需要针对性优化。

### P2 · P5→PQ 全片性能

- [x] status: done；context: archives/conversations/android-hdr-dv-display-plan-20260922.md
- acceptance: Mystery Box 在正式 PQ 输出链路、默认电池模式和明确尺寸下播至 EOS；逐段记录 VO/decoder 掉帧、GPU 频率、温度和持续可见画面，必要时定向优化并同包 A/B 验证。
- latest: P1正式代码12603 Mystery Box→PQ 3840×2160全片EOS VO2204、decoder0，GPU中位720MHz。12604诊断限宽2560×1440全片EOS VO30、decoder0。12605通用布局自动选2560×1440，PQ全片EOS VO20、decoder0；进一步修正窄视图被拉伸后，12615最终代码严格EOS VO11、decoder0，GPU中位586MHz，电池温度34→37°C，相对4K基线VO少约99.5%。HDR10/P8.4正常路径短轮、竖屏单/双视图布局缩放和全屏PQ已复核，V1无确定性阻断；12616用户真人观感通过。见 `archives/experiments/android-p5-pq-performance-12603-20260928.md`。
- final_acceptance: 12616无性能探针同代码包，首次因锁屏遮挡未触发打开，不计；解锁后同步重播，日志确认`gpu-next`/`mediacodec`、P5→PQ和2560×1440布局路径。用户现场回复“整体良好，无异常”，涵盖锐度、亮暗、颜色、流畅性与残影/拉伸检查。全片性能以12615严格EOS VO11、decoder0、GPU中位586MHz为依据；短时人眼反馈不替代全片数字。结束恢复原12492、自动亮度、熄屏。双视图单活动Surface和热切源aspect风险转P3。
- next: 进入P3生命周期与Glass片尾故障。

### P3 · P5 生命周期及片尾故障

- [x] status: done（2026-09-30 收敛）；context: archives/conversations/android-hdr-dv-display-plan-20260922.md
- acceptance: 退出重入、Surface/双视图切换、失败重试、直接 Engine 销毁后资源正确释放且持续出帧；旧 Glass 片尾紫屏根因查明并修复，完整 EOF、暂停重绘、seek 与重入无残影；Mystery Box 用于正常 EOF 回归。
- final_acceptance_map: 验收行各项证据——退出重入/seek 与重入：12639（同播放器重开 2.0 秒出画）+ 各轮全新进程启动；双视图切换：12645（同播放器双视图布局/尺寸）+ 12659（双播放器两路同时显示、图像识别左右不同实拍画面）；失败重试：12661（初始打开失败→RECOVERY_SOURCES 恢复链 10 秒恢复出帧、位置推进、退出闭合 2201/2201；P1 时代 12601 输出槽同路重试为注入补充证据）；直接 Engine 销毁资源释放：12655×3（broker 终止 mpv、线程全部退出、P5 finals 949/949、进程存活、零崩溃）；片尾紫屏修复：12632×3 命中收敛版相邻帧回退且画面正常；完整 EOF：12627×2 Glass + 12633 Mystery Box；暂停重绘：12640（帧 37 秒字节级稳定）；Mystery Box EOF：12633。低优先边界（不属验收行）：音频-only 宿主 broker 接线、transaction 同控制器热切/SurfaceProducer 路径（需 fixture 注册）、12473-12477 的 ACK 丢失注入变体复测。
- latest: 12492 P5 播至 PTS164.8 后退出重入成功，直接 Engine.destroy 仍未验。Glass 尾段 PTS约175 曾有 AImageReader `-30001`、渲染失败及紫屏；12526 两轮中一轮复现、一轮保留末帧，缺 end-file 与 buffer 身份，根因未定。清理版12576在片尾PTS174.958再次出现一次同类取图/渲染失败，但片尾截图正常、播放完成；12580在Mystery Box seek开始的旧PTS8.008也出现一次，之后45秒处继续播放并同播放器重开成功、资源闭合。12585 Glass属性0全片在PTS174.991再次出现相同取图/渲染失败。12618 SurfaceProducer 全片在EOS后复现紫屏；12621正确 Texture 路径即使保留上一张 AImage，PTS174.958 仍在287次 callback 后连续10次取图返回`-30001`，紫屏复现，故此缓存候选未通过。12622增加只读身份日志的正确 Texture 短轮未复现；末帧174.958第一次释放返回0，callback287，未见重绘请求。候选只在隔离 mpv 工作树，未提交/纳入正式产品。见 `archives/experiments/android-p5-tail-repro-12526-20260927.md`、`archives/experiments/android-p5-product-seek-reopen-12580-20260928.md`、`archives/experiments/android-p5-glass-default-12581-12585-20260928.md`。
- latest_followup: 12622再次短轮复现：Huawei HEVC flush与PTS174.974末帧release同毫秒，release返回0，但之后10次取图`-30001`、无新callback、截图紫屏。12625相邻帧回退在正确Texture路径明确命中：174.958复用174.941，相差16.683ms；EOS、正常DV logo、Back退出AImage288/288、retired0。12626同候选Glass从片头到EOS又命中174.991→174.975回退，t195画面正常，VO13/decoder0；该轮未做正常Back。候选已收敛掉高频诊断并简化回退条件，NDK编译通过，但12627新包受限环境的Gradle/ADB本地socket权限阻断，只有手工替换libmpv后的APK签名/对齐证据，**未实机运行**。mpv候选本地提交`c025cbf`；用户报告已手动推送到Goodwu/mpv，当前环境网络受限尚未独立核对远端。P3仍进行中。详见 `archives/experiments/android-p5-glass-tail-12617-12627-20260928.md`。
- source_switch_followup: 源码确认Player切源时会发送空`VideoParams`，Android控制器原先直接略过，使上一片源尺寸缓存仍参与切源间隙的布局计算。当前目录已加清空旧尺寸/已应用请求的候选。**2026-09-29 实机验收完成并提交**：① 热切源A/B（12641对照/12642候选，Glass 16:9→p84控制源2.0:1，100ms布局ping覆盖间隙）：对照包间隙内复现旧aspect中介请求（`SetSurfaceSize 996×560`/`2560×1440`），候选包间隙零请求、新源参数到达即刻正确`2880×1440`，截图全部无拉伸；② 双视图（12645）：四相位尺寸请求精确跟随槽位布局（`1440×810`/`720×405`全16:9正确）、无空参数事件、零错误、退出闭合；③ 全屏：12642热切轮即横屏全屏布局。两轮切源AImage闭合、EOS、dispose正常。未覆盖：transaction同控制器热切（需fixture注册）、SurfaceProducer路径。见`archives/experiments/android-p5-source-switch-aspect-20260928.md`。
- device_regression_12627_12633 (2026-09-29): ADB恢复后实机回归完成多轮，均自动恢复原12492/自动亮度/熄屏：① 12627重签包全片2轮：EOS到达（`eof-reached=yes`、`AUTO_COMPLETED completed=true`）、Back退出资源闭合（`P5_IMAGE_FINAL acquired=deleted=10461/10476、retired=0、empty_acquires=0`）、无渲染错误，t175/t195截图经图像识别均为正常DV标版；两轮片尾取图故障均未发生。② 正式重建12632（`/private/tmp/media-kit-p5-pq-product` e0102cf干净树 + `media-kit-p5-tail-clean-12627-arm64.jar`（含`c025cbf`回退）+ `MEDIA_KIT_ANDROID_PLAYING_START_SECONDS=170` 起播片尾段，APK SHA `60cdb743...`）短轮3轮：3/3在PTS174.958出现10次`-30001`取图失败并命中收敛版相邻帧回退（`P5_TAIL_FALLBACK requested=174.958 previous=174.941 delta=16.683ms`），t13/t25截图经图像识别全部为正常DV标版（无紫屏/黑屏），Back退出资源闭合（282/283/281 全对等、retired=0）、无渲染错误。**收敛版回退条件（10次失败+0–50ms相邻PTS，不要求callback不变）已在实机验证触发且画面正常。** ③ Mystery Box EOF轮12633（同define去起播，LOCAL_SOURCE=mystery，SHA `f2b6ac36...`）：EOS到达（~99秒与片长一致）、零取图失败、零渲染错误、Back资源闭合（5926/5926、retired=0），t13/t60为实际画面、t110为片尾落版，均图像识别确认。重建define集含 `AUTO_SINGLE_PLAYER/OPEN_ON_TAP/PREOPEN_FULLSCREEN/LOCAL_SOURCE/NAMED_LOCAL_SOURCE/P5_RPU_PIPELINE_BUILT/HDR_TRANSACTION/SURFACE_PRODUCER=false/TEXTURE_LAYOUT_SIZE/PERF_PROBE/P5_COUNTER_PROBE/DIRECT_OPEN_TRACE`（经12628–12632逐项试错复原）。证据：`/private/tmp/media-kit-p5-glass-tail-12627/12632-*`、`media-kit-p5-mystery-eof-12633-*` 系列日志与截图。
- device_regression_12639_12640 (2026-09-29): P3 生命周期补验完成：① 12639（非transaction默认入口+`gpu-next`/`mediacodec`直通，`AUTO_SEEK_AT=8→45`+同播放器重开）在 seek 边界 PTS8.008 出现10次`-30001`并命中回退（`P5_TAIL_FALLBACK requested=8.008 previous=7.991 delta=16.683ms`）后**零渲染错误**——12580 旧JAR同位置的 `Failed rendering frame!` 边界问题被同一回退消除；seek后45秒实际画面、重开后2.0秒出画（t25/t43图像识别正常，t13纯黑经时间线核对为源重开间隙），VO停止资源闭合（1687/1687、retired=0、held_after=0）。② 12640 暂停重绘：媒体8秒暂停（`ANDROID_HDR_MEDIA_PAUSE timePos=8.000 pause=yes`），t13/t25/t50 三张暂停帧截图字节级一致且图像识别为正常炉火画面（无紫屏/残影/重绘），退出资源闭合（474/474、retired=0、empty_acquires=0）。详见 `archives/experiments/android-p5-tail-c025cbf-regression-12627-12640-20260929.md`。
- temp_reconcile_priority_1_done: `/private/tmp/media-kit-p5-mpv-product` 的全部门槛已于2026-09-29完成：12632短轮×3命中回退、12627全片×2 EOS+Back闭合、12640暂停重绘、12639 seek/重入、12633 Mystery Box EOF（见 device_regression 各条）；`c025cbf` 已独立核验存在于 Goodwu/mpv 远端 `feature/android-p5-sdr-direct-yuv` 分支（`git ls-remote` 确认 `c025cbfeda48...`），JAR 留存 `/private/tmp/media-kit-p5-tail-clean-12627-arm64.jar`。该目录已删除（其原挂接的主仓库 `media-kit-p5-mpv` 先前已删，删除后 git 链接本已断开，源码以远端分支为准）。
- temp_reconcile_done_20260929: `media-kit-p5-jar-rebuild-20260927`、`media-kit-p5-app`、`media-kit-ffmpeg-p5-stream-2215`、`media-kit-p5-jar-ffmpeg-20260927` 的独有差异已逐文件判为旧探针/私有构建开关或被正式产品等价包含；P0产品链路、FFmpeg RPU与P3正式12632短轮已具相应回归证据。四个工作树及其生成文件于2026-09-29逐目录删除，源码补丁留存于`archives/experiments/android-private-tmp-patches-20260928/`；这不宣称P3所有生命周期场景通过。
- engine_destroy_12646_12657 (2026-09-29/30): 直接 Engine 销毁崩溃**已根因修复并完成资源闭环**。根因：release 模式 `InitializerNativeCallable` 把 `NativeCallable.listener` 蹦床注册为 mpv wakeup 回调，isolate 拆卸使蹦床可执行内存失效，播放中的 mpv 线程下次 wakeup 即调用已释放蹦床（上游 #1340 同类，仅修了 debug）。二分链：裸 Player/暂停销毁不崩（12647/12648）、disposeAll（12649 3/4崩）、posted 延迟（12651 4/4崩）、钉库（12652 3/4崩）均排除。**修复=owner broker**：`MpvOwnerBroker.java`+JNI（清空 wakeup 回调主线程同步执行 + `mpv_terminate_destroy` 在专用 broker 线程）+ Dart 注入钩子注册句柄。**12655 播放中直接销毁 3/3 零崩溃且资源闭环**（P5_IMAGE_FINAL 949/949 由 broker 终止触发、mpv 线程全部退出、进程存活、destroy 30ms 不阻塞平台线程）；**12657 正常 Back 零回归**（unregister 到达、broker 零活动、2263/2263 闭合）；双重释放经构造分析无窗口。P3「直接 Engine 销毁后资源正确释放」验收达成。剩余边界：音频-only 宿主未接线。见 `archives/experiments/android-p5-engine-destroy-12646-20260929.md`。
- failure_retry_dual_player_12658_12661 (2026-09-30): P3 最后两项子验收完成。① 失败重试（12661，产品路径）：初始源不存在→`AUTO_SOURCE ERROR`→`RECOVERY_SOURCES` 恢复链打开已注册源（含 243MB staging，10 秒恢复）→播放位置持续推进、截图图像识别为正常画面（瀑布/火山场景切换）、退出闭合 2201/2201、零崩溃。12658 的输出 Dispose 注入经判定为产品不可达形态（通道层绕过控制器簿记→槽复用黑屏；mpv 侧正常），教训已记；12660 恢复源被 staging SHA 校验拒绝（Mystery 未注册）后改用已注册源。② 双播放器双视图（12659）：第二 Player 独立播放 Mystery Box，两输出同时活动（并存 setSurfaceSize 720×405），退出两输出先后 Dispose、P5 finals 326/326、零崩溃；图像识别确认左右两半同时显示不同实拍画面。见 `archives/experiments/android-p5-failure-retry-dual-player-12658-12659-20260930.md`。
- next: P3 验收行各项均已具实机证据（见上方 latest/device_regression/engine_destroy/failure_retry 各条）；剩余低优先边界：音频-only 宿主 broker 接线、transaction 同控制器热切与 SurfaceProducer 路径（需 fixture 注册）。

### P4 · 独立色彩数值验收

- [x] status: done（2026-09-30 比较完成，**结果为发现颜色回归**——修复任务另立）；context: archives/conversations/android-hdr-dv-display-plan-20260922.md
- acceptance: 对实际 P5 输出逐帧核对 RPU，覆盖 seek/flush/重开；明确参考母版、目标空间和映射策略，做同 PTS 独立数值比较。
- latest: 逐帧 RPU 核对与 seek/flush/重开（10440/12512）此前已完成；2026-09-30 完成同 PTS 独立数值比较：参考母版/目标空间/映射策略明确化（BT.2020/PQ/full/1000nit；DoViBaker 独立实现 + 主机 libplacebo 离屏浮点参照，全程不用 mpv 截图）。**主机↔DoViBaker 两独立实现一致；设备实际渲染输出（GPU 整帧 RGBA16F 读回）为离群方**：Sol Levante 帧240 MAE≈(2726,2603,10212)/65535、4K50 帧500 (4716,876,8388)，而 8370 时代同方法设备↔主机仅 (41,21,53)——**P0/P1 产品化窗口（9/25→9/28）引入约100倍恶化的颜色回归**；隔离到 mediacodec 解码路径（`hwdec=no` 软解时偏差消失、三通道偏置归零）。已排除通道顺序/翻转/错镜头RPU/mpv截图路径。见 `archives/experiments/android-p5-numeric-color-20260930.md`。
- temp_reconcile_done: DoViBaker 参考（`/private/tmp/media-kit-dovibaker-reference`）与 ffmpeg-dvtest 参照的用途已核清并在 2026-09-30 比较中全部重建使用（输出与 9/25 记录 SHA 逐一相同）；源码快照在 patches 目录。两个目录可按门槛删除。
- next: 转入新任务「P5 mediacodec 路径颜色回归修复」（见下方）。

### P5 · mediacodec 路径颜色回归修复（2026-09-30 由 P4 发现）

- [x] status: done（2026-09-30 全链闭环：定位、修复、数值验收、产品集成、视觉复跑与真人确认全部通过）；context: archives/experiments/android-p5-mediacodec-color-fix-20260930.md（P4 原记录 `android-p5-numeric-color-20260930.md` 的 100 倍结论已修正）
- acceptance: 定位并修复 mediacodec 解码路径的 P5 颜色偏差，修复后同 PTS 三方比较恢复 ≤100/65535，并复跑 P0/P1/P2 关键视觉验收。
- latest: **双重根因均已数值闭环并完成产品集成**。① P4 的 100 倍偏差是读回装置缺陷：读回 JAR 链接的旧前缀 FFmpeg（9/24 stage-merged 补丁世代）挂载需 `debug.media_kit.p5_rpu_probe=2` 属性而轮脚本未设（`src_dovi=0`、`direct=0`）；产品 JAR（fff3ee7）挂载正常——产品轮 `direct=1`、f240 挂载 RPU 与码流第 240 帧字节一致（size 245、FNV `d34ff55e` 全流索引核对）。② 真实回归 ~0.3%：华为硬解对 10-bit HEVC 输出 8-bit NV12（AHB 0x325；copy 路径码值对软解 ≤3/1023 铁证），GLES 外部 YUV 采样按 code/255 归一化而 dovi 重塑域按 code/1023 解释 → 信号被放大 1023/1020（9/25 sidecar 时代 `code_scale=1020/1023` 修正被产品化重写丢失）。**修复（mpv fork `398d0c3`，已推送 Goodwu/mpv）**：aimagereader 检测 8-bit YUV AHB 格式时对帧 dovi 元数据就地精确重标定（pivot×k、poly/MMR 系数按阶数×k^-d，k=1023/1020）。**数值验收达成**：设备↔主机 Sol f240 (47,50,70)、4K50 f501 (50,19,58)/65535 均 ≤100（修复前 (185,106,72)/(160,91,83)，断链时 (2726,2603,10212)/(4716,876,8388)）；软解阴性对照 (12,13,17)。**产品集成与视觉复跑（自动）完成**：正式 JAR（fff3ee7 libavcodec+前缀，`dad30ae2…`；教训：产品链接必须用 fff3ee7 世代 libavcodec，误链 mkp4prefix 旧版会复演 `direct=0`）+ 三正式 APK（12680 Glass SDR/12681 Mystery SDR/12682 Mystery PQ），三轮全片实机验收均 `direct=1`+`P5_DOVI_RESCALE enabled`+EOS、零渲染错误，10 张截图像素统计全部正常画面/落版（PQ 轮 gpuPlatformHdr=true、与 SDR 轮同帧 RGB 均值差 ≤0.4）。
- evidence: 读回轮 12672–12679 全链与主机模拟（实验记录详列）；三轮产品视觉轮 `/tmp/p5-colorfix-{mystery2-12681,glass-12680,pq-12682}-*`；APK 留存 `/tmp/media-kit-p5-colorfix-1268{0,1,2}.apk`；**真人确认 2026-09-30 通过**（用户现场观看修复版 Glass Texture SDR 播放，答复「画面正常无异常」）。
- next: 已关闭。遗留研究项（8-bit vs 9/25 10-bit 缓冲之谜）**已于同日判别实验解决**（`archives/experiments/android-p5-buffer-bitdepth-mystery-20260930.md`）：表面缓冲从未变为 8-bit（两代均 0x325 Main10 10-bit、驱动 Y2Y 按 /1020 归一化），变的是产品化丢失 code_scale 补偿（398d0c3 已等价恢复）；post-fix 残差不含量化成分（低于 8-bit 量化噪声量级、与量化误差场零相关），「恢复 10-bit 降残差」期望作废，无需进一步修复。仅 398d0c3 源码注释「0x325 = 8-bit」措辞待后续 fork 提交顺带更正（行为正确）——**已于同日归一时更正**（`media-kit/android` `5379756`，仅注释、行为不变）。

## 其他当前任务

- [x] media-kit 主仓合并上游 main（236 提交）回归单线
  - status: done（2026-09-30 合并 + 静态验证 + P5 五项实机验收全部通过）；context: archives/experiments/android-media-kit-main-merge-assessment-20260930.md、android-media-kit-main-merge-acceptance-12700-20260930.md
  - acceptance: `fix/darwin-video-output-rebuild-barrier`（或其继任集成分支）合并 origin/main（上游 236 提交）后构建通过，并复跑 P5 关键实机验收（颜色数值、片尾回退、EOS、直接销毁、PQ 首帧）无回归；main 成为唯一维护线。
  - final_acceptance: 合并提交 `a886f556`，63 处冲突分层裁定（评估报告为蓝本）；四包 analyze 通过（OHOS 既有 4 错误除外）；12700 Glass SDR / 12701 Mystery PQ / 12702 直接销毁三轮实机验收全部通过——两全片轮 direct=1 + RESCALE k=1.002941 + 片尾回退命中 + EOS + 闭合 8376/4483 全对等，销毁轮零崩溃进程存活 900/900 闭环；APK 库集与已验收 12680 一致，native 未变。遗留：上游亮度/音量控件特性未吸收、Linux 侧待 Linux 环境回归、严格数值读回可按需补跑。main 已快进为唯一维护线；同日清理 fork 全部 11 个废弃远端分支（4 个已包含直接删、7 个先打 archive/*-202609 tag 再删，见归一记录追加节），Goodwu/media-kit 仅剩 main 单分支。合并提交漏缴的三处构建后修复（FocusNode 移植/未用变量/analysis_options）以跟进提交补全——实机验收构建自工作区，已含这些修复，验收结论不受影响。

- [ ] Android HDR10 / DV P8.4 显示与原生 HDR 首帧闭环
  - status: in_progress
  - context: archives/conversations/android-hdr-dv-display-plan-20260922.md
  - acceptance: 固定素材和设备能力，核对 HDR10 PQ、P8.4 HLG 的真实后端、Surface 格式、系统合成、连续全屏画面及 SDR 复位；P8.4 无 HLG 路径与原生 DV 能力单独说明。原生 HDR 从触摸到视频内容小于2秒、争取1秒，补冷/热、重入与输出切换。最高亮度只用于短时人工观察，结束立即恢复自动亮度并熄屏。
  - latest: HDR10、P8.4 全屏画质和流畅性已获用户认可；12537 P8.4 HLG 三轮触摸按下→Surface 内容0.670/0.676/0.623秒，12538 HDR10 PQ 为0.653/0.648/0.630秒，视频层分别为 BT.2020 HLG/PQ。P8.4 Texture→SDR 普通入口人工验收通过：轻微偏淡可接受、流畅、声画同步，用户感受约1秒内出画，同轮读回0.844秒。读回还不是面板光学时间。见 `archives/experiments/android-native-hdr-firstframe-12537-12539-20260927.md`、`archives/experiments/android-p84-sdr-human-acceptance-20260927.md`。
  - next: 扩充原生 HDR 冷/热、重入、连续帧及 SDR 复位证据；P5 输出和首帧单列于 P1，不以 HDR10/P8.4 代替。
  - temp_reconcile: `/private/tmp/media-kit-firstframe-sdr-20260927` 的5个App/plugin文件、`media-kit-firstframe-mix-20260927` 的9个修改及868个删除状态项尚未与当前代码逐项比较；后者只保存了修改补丁，删除项不可直接重放。先隔离比较真正的首帧/输出行为，再针对SDR、HDR10、P8.4冷/热打开与输出切换做相应实机回归；记录冗余或迁移结论后删除工作树。不要把大量删除当成产品清理。

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
  - next: 核验清理中再次点击、失败重试和全屏组合。任意宿主直接 FlutterEngine.destroy 需先做独立于 Dart 的 Android 原生播放器 owner broker，统一 mpv 调用、事件/hook、终止和视频输出引用；先以无视频 Player 实机直接 destroy 证明终态，再接 SDR PlatformView、两种 Texture、HDR/P5，详见本条 context。继续通用失败 disposal/global-ref 定量闭合、连续可见帧与 mpv WID 回读，再决定提前停轨默认值；P5 专属双视图与属性序列故障归入 P3。**2026-09-29 更新**：owner broker 第一步已落地——P5 Texture 播放中直接 destroy 的确定性 SIGSEGV 根因（release NativeCallable wakeup 蹦床随 isolate 失效）已修复（12653 播放中销毁 4/4 零崩溃、12654 正常路径无回归），无视频裸 Player 终态已证（12647）；broker 现覆盖 wakeup 回调清空与视频输出释放，**mpv 终止与音频-only 宿主接线是下一增量**。详见 `archives/experiments/android-p5-engine-destroy-12646-20260929.md`。
  - temp_reconcile: `/private/tmp/media-kit-mpv-p5-replay-2214`（7文件）、`media-kit-mpv-p84-rebuild-2213`（6文件）、`media-kit-mpv-upstream-reader3`（4文件）均是未提交的旧mpv生命周期实验。逐项比对当前产品输出与现有复现记录；若保留修正，先跑双视图B存活、失败重试、Home返回、直接Engine销毁及资源闭合；无独有修正的目录在记录结论后删除。

- [ ] 整理 `archives` 的主题结构与引用
  - status: planned；context: archives/conversations/android-hdr-dv-display-plan-20260922.md
  - inventory: 2026-09-28 有 `archives/experiments` 顶层221篇Markdown、`archives/conversations` 8篇；实验记录中 P5 约133篇、HDR约27篇、P8.4约18篇、HDR10约13篇，缺统一入口，当前新增的临时工作树清单又增加查找负担。
  - acceptance: 先为每个活跃任务建立从 `TASKS.md` 可直达的主题索引，明确当前结论、证据顺序和旧实验状态；再按主题迁移零散实验文件，保持原始证据与每个topic唯一conversation；同步修正 `TASKS.md`、conversation、脚本和文档内的引用，检查链接与文件数。只有确认新路径和Git历史可追溯后才删除旧位置，不批量丢弃未知记录。
  - priority: P3片尾/切源临时改动的成熟和实机回归优先；归档先做P5/P3索引，再处理HDR10/P8.4与首帧，最后整理其余历史。此任务与临时目录清理一起推进，避免再次出现证据只在 `/private/tmp` 的情况。
  - next: 生成文件到任务的映射、识别重复记录与外部路径引用，制定最小迁移批次；每批先更新入口和链接，再迁移、核验，最后清除确认冗余的旧文件。

- [ ] 排查 Android HDR 天空渐变层纹
  - status: deferred_by_user
  - context: archives/conversations/android-hdr-dv-display-plan-20260922.md
  - acceptance: 同 PTS 对照片源、解码/合成、输出位深和屏幕处理；若有可行改法，保持 HDR10/P8.4 的亮暗、颜色与全屏流畅性，再请用户人工确认。
  - latest: 最高亮度全屏验收中 HDR10 天空有层纹、P8.4 较轻，其余画面良好。按用户要求先记录，本轮不修；关闭抖动没有明确性能收益，也不是已验证的层纹修复。

## Blocked（等待输入或外部条件）

- [x] 六个已判冗余P5临时工作树的删除：先前 `rm -rf -- ...` 被自动安全审查拒绝；2026-09-29改用逐项核对后的精确路径 `rm -r -- ...` 成功删除，逐目录复查均不存在。其他临时工作树仍按对应任务保留，ADB 阻断已解除。

- [ ] 在真实 OHOS 设备上继续验证 native output 生命周期
  - status: blocked_waiting_for_device
  - context: archives/conversations/native-output-rebuild-20260920.md
  - acceptance: 原生输出实际呈现、后台/前台、退出/重入及 Surface 重建后持续播放且资源闭合；区分实体机、模拟器与静态检查证据。
  - latest: 2026-09-27 当前主机 `hdc list targets` 返回 `[Empty]`，没有可连接的真实 OHOS 设备；待设备接入后重新核验身份、包与运行状态，再继续实机验收。

## Closed（结案，未达原门槛）

- [x] 原统一素材范围（含Glass P5）首个可辨画面小于2秒：**未达成并结案；用户现改用P8.4另立上方验收项**。指定Glass P5片头约2.052秒黑场，保持从片头原速播放时仅素材时间即超过2秒；物理全屏受控读回可辨内容三轮3.543/3.374/3.625秒。SDR、HDR10 Texture→SDR、P8.4 Texture→SDR在已预建全屏路径的受控三轮均低于1秒；无同包关闭预建A/B，不能证明未经修改也达标或全部收益来自预建，亦不覆盖普通入口、光学触摸起点或原生HDR。预建通用入口及约1.41秒P5 A/B/A收益保留；详情与证据见`archives/experiments/android-first-visible-two-second-closure-20260927.md`。

## Recently Done（最近完成）

- [x] mpv fork 分支归一与发布基线：4 自定义分支收敛为 `media-kit/android` 单分支，发布 tag `media-kit-v2026.09`（398d0c3）+ 三件套发布链固定（FFmpeg fff3ee7 / libplacebo c9fd879 / JAR dad30ae2…）；av_log 修复 cherry-pick 入主线，实验路线 tag 归档。`archives/experiments/android-mpv-fork-branch-consolidation-20260930.md`

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
