# Android SDR 直连呈现轻量化优化方案

- 版本：v2.1（2026-10-17）——v2 经 Specialist 复核 **UNBLOCK**；v2.1 仅吸收复核非阻断建议与文字勘误，机制/分期/定级零变化
- 增补（2026-10-17，用户决策落地）：`sdrEmbed` 由显式 opt-in 改为**能力范围内默认启用**（「LG 默认就用 sdrEmbed，超分无效。不要加开关了」）——G4 与 P2 节已按默认启用语义改写，**V2 复审待办**（Lead 复审后统一提交）
- v1 → v2 变更摘要：修正 embed/SurfaceTexture 混写；撤回按 topology 收窄 `_requiresMediacodecCopy` 的写法；撤销 C3 "压队列省 90MB" 机制改为只读归属调查；C4 移出本方案归 DV004 独立线；C1 收益降为待验证假设并改为单变量实验制；§0 证据表述降级为"观测与假设"分离；分期重排（P0 证据修正先行）
- 状态：v2 修订后待 Specialist 复核确认解除 BLOCK；全部工作包实施前需各自审核
- 证据基线：`/tmp/w5-verify-20261017/lg-sdravc4k/`（LG H870DS/API24 三轮实机：播放轮、系统播放器对照轮、两路径资源配对轮）
- 关联开放线：DV004/复核门竞态（C4 归属）、marble AVC vendor 瞬态（不在本方案范围）

## 0. 背景与证据（观测事实与假设分离）

LG H870DS（API24，Adreno 530，1440p 屏）播放 `4k-sdr-avc.mp4`（4K H.264 Main 29.97fps + AAC）实测。

**观测事实**（原始证据可复核，16 采样点差分 top / kgsl 计数器 / meminfo）：

| 维度 | lab（sdrDirect×texture：mediacodec-copy → CPU upload → gpu-next） | 系统播放器（NuPlayer → SurfaceView → HWC 直出） |
| --- | --- | --- |
| 播放正确性 | PASS，播放时间推进比 0.9999（注：这是时间推进比，非"帧呈现率"），EOS/dispose 闭合 | PASS，全片播完 |
| 丢帧计数 | decoder-frame-drop=0（mpv 自身 wrapper 计数）；mpv `frame-drop-count`（VO 调度层）=161（≈2.2%） | 有限采样窗（≈5% 覆盖）1×213ms 呈现停顿；两窗干净 |
| CPU（差分均值） | app 进程 20.1%（差分第二屏 16 点，范围 20–21；早期记录的 15–21 混入首屏累计值，v2.1 勘误）+ media.codec 15.9%，不经系统 extractor/mediaserver | videoplayer 未进入 top -m40 名单（记为"截断未测得"，不作 <1% 断言）+ media.codec 3.7% + extractor 0.8% + mediaserver 5.1% |
| GPU 3D busy（设备级） | 55.6%（54–57） | 0%（overlay 走 HWC，不占 3D 计数器） |
| PSS | app ≈400MB | app ≈25MB |
| media.codec 进程 RSS | 139848K（≈139.8MB 十进制） | 5800K 量级（≈5.7MB）（注意：系统轮同路径分配了 11/15 个 output buffer 而 RSS 更低——两路径内存映射与统计口径不同，不可按同一公式换算；RSS 一律按原始 K 字段计） |

**不做的事实声称**（v1 曾过度归因，v2 全部降级为待验证假设）：

1. ~~"解码不是瓶颈"~~ → 观察：两路径硬解组件相同（OMX.qcom avc）、mpv 侧 decoder-drop 计数为 0。但系统轮无对应 decoder-drop 计数证据（`dumpsys media.codec` 采集为空已登记），mpv 计数只覆盖自身 wrapper——零计数不能排除解码延迟/供帧不及时。
2. ~~"VO 丢帧根因=渲染端跟不上节拍"~~ → 观察：161 次丢帧发生在 VO 调度层（vo.c 按帧期限计丢）。根因定位（GPU shader/解码供帧/CPU 上传/调度/同步等待）未做，列为 P0 待测。
3. ~~"GPU 55.6% ⇒ gpu-next 是主要负载"~~ → 设备级计数器，支持"lab 整条路径 3D 负载更高"，不支持模块占比归因。
4. ~~"差异全部在呈现路径"~~ → 两轮还更换了 demux（mpv 内置 vs 系统 extractor）、音频链（内嵌 vs AudioTrack via NuPlayer）与调度栈。呈现路径是**重要候选解释**，非已隔离变量。
5. 帧推进 0.9999 语义勘误：是播放时间推进比；"偶发丢帧"的用户观察与 161 次 VO 丢帧计数、213ms 呈现停顿互相印证，但不等价。

**修订后的证据结论**：同文件播放中，lab 路径观察到更高的可见进程 CPU、设备 3D busy、app PSS 与 codec RSS，并出现 161 次 mpv VO 丢帧计数；系统路径有限采样窗内出现约 213ms 呈现停顿。现有证据尚不能隔离丢帧根因或各模块负载贡献。

关键代码事实（Specialist 核证通过）：

- copy 兜底落点：`hdr_strategy_realizer.dart` `_requiresMediacodecCopy`（`sdkInt > 0 && sdkInt < 26`）。**作用域警告**：该 helper 有三个调用方——`_baseLayerConvert`（HDR **PlatformView**+gpu-next）、`_toneMapSdr`、`_sdrDirect`（均 texture）——**不是 Texture 专属**；按 topology 收窄它会破坏 HDR PlatformView 的 GPU import 路径（AImageReader import 是 GPU importer 的 API26+ 依赖，见 `~/src/mpv/video/out/hwdec/hwdec_aimagereader.c:147–156,184–207,251–253`）。**本方案不修改该 helper。**
- embed 路径存活且被产品消费：`vo_mediacodec_embed.c`（wid=Java Surface 直入 MediaCodec；flip 时 releaseOutputBuffer，默认 boolean render-mode，c11426b67a 增 timed 实验）；realizer 已有两条 embed 路由（native-DV、baseLayerDirect，`:235–255,289–309`）**本就不调用 copy 判断**。
- embed VO ≠ SurfaceTexture：SurfaceTexture latch/OES→2D FBO 在 `hwdec_surfacetexture.c`（另一条路径）。embed VO 本身无 OES 绘制。SurfaceTexture importer 的 SDR 适配为**独立备选研究，未列入本方案工作包**（须另立包，不得借用 HDR YUV arm 授权；执行者不得据本行引用自行扩大范围）。
- 复核门契约现状：`startsWith('mediacodec')` 已覆盖精确值 `mediacodec` 与 `mediacodec-copy`，另覆盖 `surfacetexture`；embed 观察契约要求实际 `hwdec=mediacodec` 且 `pixelFormat=mediacodec`；附着标签 `X→X_mediacodec` 形状已白名单化。**取值已覆盖 ≠ 任何附着时序已覆盖**——新载体的完整附着时序必须重放到现行门测试。
- 功能限制：embed VO 缺字幕渲染、OSD/OSC、视频滤镜（`~/src/mpv/DOCS/man/vo.rst:727–733`）——消费方需要这些功能时的准入/保留 Texture 规则是 C2 的必要部分，不是可选项。（**2026-10-17 注**：sdk16-25 SDR 默认路径经用户决策接受超分/滤镜/OSD 不执行——本条对该人群/该路径构成显式例外，见 §4 风险 7 与 P2 默认启用改写条目；其余路径不变。）

## 1. 目标与非目标

目标：

- G1 SDR 直连播放的资源占用向系统直出收敛——**以 P0 实测差量为准设定量化阈值，不预设**（v1 的"app CPU ≤12%/GPU ≤25%"降级为探索目标，非承诺）。
- G2 消除 lab 路径的 VO 级偶发丢帧（161 → 收敛，验收用"统一 present 节拍指标 + VO 计数"双指标；present 节拍为主）。
- G3 HDR 路由/会话/复核门**契约语义零变化**；`_requiresMediacodecCopy` 及既有 HDR 载体边界逐位不动；一切设备差异走能力化声明（禁设备名，2026-10-16 用户裁决）。
- G4 画质与功能不回退：颜色/亮度按 LG 目视协议；**另含缩放清晰度、字幕、OSD/OSC、滤镜、交互功能等价性评估**（embed 限制清单的准入判定输入）。功能需求区分**会话固定需求**（选载体时判定）与**运行中需求变化**（播放中启外挂字幕/滤镜/OSD）——后者由 P2 定义受控重建或显式拒绝，不做未经审核的隐式切载体。（**2026-10-17 注**：sdk16-25 SDR 默认路径经用户决策接受超分/滤镜/OSD 不执行——「画质与功能不回退」对该人群/该路径构成显式例外，见 §4 风险 7 与 P2 默认启用改写条目；其余路径不变。）
- G4 运行中需求变化契约（P2 实施补充；**2026-10-17 用户决策后按默认启用语义改写，V2 复审待办**）：`sdrEmbed` 选项解析已翻转为**能力范围内默认启用**（用户决策原文「LG 默认就用 sdrEmbed，超分无效。不要加开关了」；unset(null)=默认启用、显式 `false`=退出逃生口、显式 `true`=同默认；不加用户可见开关）。默认路径=sdk16-25 设备（`_requiresMediacodecCopy`）的 SDR 会话；**mpv 侧 GL 功能（超分 shader/滤镜、字幕、OSD/OSC）在该默认路径不支持、声明与否都不执行——已接受的产品取舍，库不自动检测 GL/shader/滤镜使用**。Flutter 层叠加功能（弹幕/Flutter 字幕）合成于平台视图之上，单独评估，不受此选项覆盖。播放中新增这些需求：保留其他有效选项、置 `sdrEmbed:false`，经 `setOptions` 受控重开（`hdr_video_session.dart` setOptions 的既有 stop→重规划→重建输出机制）确认成功后再启用功能；不支持该受控重开流程的调用方必须显式拒绝功能请求。禁止把直接向 Player 写滤镜/shader 当成自动切回 Texture 的机制（embed VO 不执行它们，只有受控 `sdrEmbed:false` 重开回到 Texture 载体）；screenshot-raw 兼容性未实测，不纳入已验证承诺。准入范围不变：sdrDirect + `_requiresMediacodecCopy`==true（该 helper 与三调用方逐位不动），另增源级硬解声明抑制（完整 census 无受支持硬解行不生成 embed 候选）；显式 `preferCopy` 意图仍胜出。

非目标：HDR 载体矩阵不动；marble vendor 线不动；不修改门发布契约既有语义；P8.4 tone-map 卡顿线不并入；本方案不做任何 wrapper 改动（经调查证实必要后走原生 B 线独立立项）。

## 2. 工作包

### P0 证据修正与基线冻结（先行，机械采集 V0 / 因果判读 V1）

1. 运行时最终配置快照：lab 播放态抓取全部 vd/vo/libplacebo 生效属性（已知默认已含 `scale=bilinear`、`dscale=bilinear`、`dither=no`、`correct-downscaling=no`、`linear-downscaling=no`、`sigmoid-upscaling=no`、`hdr-compute-peak=no`（`real.dart:2674–2692`）；Texture 路径 `target-colorspace-hint=auto` 是已识别的仅存非 `no` 项）。产出=差量清单，**只对确认启用且有成本的处理立项**。
2. 视频输出 buffer 实际尺寸测量：`matchTextureOutputToLayout`（`platform_video_controller.dart:236–242`，默认关）当前是否生效、纹理输出是源分辨率还是布局分辨率——决定"输出尺寸"实验是否成立。
3. 丢帧根因观测设计：present 节拍（SF latency，与系统轮同口径）+ VO 计数 + 供帧/调度时间戳，定位 161 次丢帧的归属层。
4. 统计口径定义：app CPU 截断语义、PSS/RSS 不相加、单位统一（RSS 按原始 K 字段）；**present 节拍指标的层语义标注**——texture 路径的 SF 层可能记录 Flutter 合成提交、embed 路径记录独立视频 Surface 提交，须标注采样层与重复帧/缓冲提交→实际视频呈现的对应关系，无法对应时分别报告不直接比较丢帧率；**阈值冻结时点**——P0 完成后、读取优化结果前冻结验收阈值；配对实验 AB/BA 或 ABAB 顺序并记录温度/频率/实际媒体 PTS；短窗资源采样与全片 drops/EOS 验收分开记账。
5. API26+ direct texture 命中率检查：direct→copy→software 执行目录（`:139–181`）在现代设备上是否实际命中 direct、失败原因、与 `preferCopy` 偏好排序（`video_route_option_review.dart:93–129`）的交互——这是"API26+ 已存在、不是待发明优化"的核实项。

### P1-A embed 产品链可行性实验（主线；实验判读 V1，立项后候选接入 V2）

- **机制（修正后）**：`mediacodec_embed + hwdec=mediacodec + SurfaceView`——wid 直接是平台视图 SurfaceView 的 Surface，解码输出直送 Surface，由 HWC 合成；**embed VO 无 OES 绘制步骤**，GPU 是否接近 0 取决于 HWC/Flutter 合成实测，不预设。**HWC 合成是实验中的观测判定项（SF composition 类型核实），不是 embed 的必然保证——overlay 未被分配不判失败，也不据此反推存在 OES 绘制。** render-mode 用 boolean 默认；timed 单列实验不混采。
- **探针规格（同输入同输出语义等价，2026-10-17 复审标准）**：同 APK/native 构建身份、同原始文件+hash、同音轨同速度、同显示区域与采样区间；同产品 FFmpeg/mpv 解码链（禁手工 CSD/合成流/render=false）；对照轮只变呈现链；验证持续可见帧、实际 present 节拍、A/V 同步、EOS、资源释放；完整附着时序重放到**现行不改语义**的门测试；覆盖 seek/暂停恢复/后台返回/Surface 重建/全屏/双视图；同 PTS 颜色对照（**先确认截图能捕获该合成层——LG DV HWC overlay 截图限制的既有教训，不得以黑图判黑屏**）；"native 链可行性"与"产品会话可行性"分开记账。
- **门契约判定规则**：观察到 `mediacodec` 值/`h264_mediacodec` 附着→契约已覆盖，按时序重放判定；若观察到 `surfacetexture` 值→**不得**借硬解白名单判通过（不符合 embed 观察契约），先查实际执行路径。
- **能力建模（修正后）**：不新增 `avc×surfacetexture` 命名、不挂 `HdrDataSpaceExtInfo`（那是 vendor dataspace 域）。采用**通用 Android 执行能力快照**分开表达：①后端是否提供 embed Surface presenter；②精确 source 是否有可用硬解能力；③当前输出与所需功能是否兼容该 presenter（`hdr_output_contract.dart:26–47` 已能生成 embed/PlatformView 输出契约，复用之）。先论证新增字段的必要性（现有 source decode support 已能表达哪些）。
- **明确不动**：`_requiresMediacodecCopy` 三调用方逐位不变；W1 受管生命周期/arm 条件不变；产品 wrapper 代码不改。
- **可行性判定即停条件**：解码/出帧/EOS 任一不成立，或门时序不可满足，或功能限制不可接受（需字幕/滤镜的内容保留 Texture 载体的准入规则在立项时一并定义）。

### P1-B 有证据才做的单变量实验（并行，V1）

- 候选 1：`target-colorspace-hint` SDR 语义实验（Texture 路径现值 auto——确认其对 SDR 的实际行为与成本，改变它需验证颜色语义而非仅 decoder facts）。
- 候选 2：输出尺寸实验（若 P0-2 证实输出为源分辨率）：同源同可见区域下输出布局分辨率的资源差量。**不是降清晰度方案**——最终可见区域逐像素**对照**（用于比较，非要求逐像素相等：缩放发生阶段改变可产生数值差异），预先定义清晰度/边缘/色彩/功能不退化判据，不以任意容差掩盖回退。
- 候选 3：P0-3 定位出的任何确认成本项的单变量处理。
- 规则：无差量则删除，不强求落地；涉及 `_setOwned` 合法空值所有权的，单独验证捕获/恢复/失败分支（`hdr_player_backend.dart:122–135` 要求原值非空，ICC 等合法空值不能直接塞入）；`vdLavcOptions`/`mediacodecEmbedRenderMode` 的 native-DV 配对契约**不得**当作普通配置注入模板复用（`:153–165`）。

### P2 SDR presenter 能力准入与候选接入（P1-A 成立后立项，V2）

- 新增 sdrDirect×embed 执行候选：复用既有 baseLayerDirect/输出契约/SurfaceView 接线部件；偏好排序显式重审（跨 topology 加候选后 `preferCopy` 语义不保自然成立，`video_route_option_review.dart:93–129` 需逐条核对）；失败策略、功能兼容准入、双视图/重建/全屏生命周期回归、HDR 矩阵全绿。
- 运行中需求变化契约（V2 审核补充）：同 G4 补充条目——`sdrEmbed` 选项范围与五条规则、受控重开机制位置（`hdr_video_session.dart` setOptions）、不支持重开流程的调用方显式拒绝义务、Player 直写滤镜/shader 非切换机制、screenshot-raw 未实测。另按 Lead 裁定（P2 观察 2）：显式 `preferCopy` 意图按设计保留（LYA 轮契约），在生成派生处**抑制**（非降序）embed 候选，冲突时 copy 意图胜出（实现：`hdr_route_planner.dart` `_evaluateCandidates`）。
- 默认启用改写（**2026-10-17 用户决策落地，V2 复审 APPROVE-WITH-CHANGES 已收口**）：`VideoRouteOptions.sdrEmbed` 保持 nullable、API 面零增删，解析翻转为 unset=默认启用（能力范围内）、显式 `false`=退出、显式 `true`=同默认（实现：`EffectiveVideoRouteOptions.resolve` 的 `requested != false`；`hdr_video_session.dart` `_settingsValues` 携带显式 `false`，退出语义在 setPreference/setPolicy 往返中保持）。准入仍为 sdrDirect + `_requiresMediacodecCopy`==true（helper 与三调用方逐位不动），API≥26 与 sdkInt=0 行为零变化；源准入为**精确三态判定**——仅 census 明确声明 hardware decode `unsupported` 才抑制，`unknown` 行（含完整 census）与缺失 census 不抑制（V2 纠正：原「完整 census 无受支持硬解行就抑制」表述过强，实现与修正后注释一致），运行时复核仍是决策点。**证据边界（V2 裁定表述）**：现默认选择的同一 embed 执行路径已在 LG H870DS/API24 的受控显式 opt-in 会话中完成端到端验证；本次未重新实测默认构建，其他设备待验证。默认路径上 mpv 侧 GL 功能（超分 shader/滤镜、mpv 内字幕/OSD）不执行为已接受产品取舍（本条与 :41/:50/:51 的旧「需要功能时保留 Texture/不回退」约束相比，**对 sdk16-25 SDR 默认路径构成显式例外**，其余路径不变）。lab `MEDIA_KIT_ANDROID_SDR_EMBED` define 保留为显式覆盖（幂等），initState guard（须 HDR_TRANSACTION=true、禁混 EMBED_PROBE）不变。
- 不改既有 HDR copy 边界/W1 授权。

### 独立线 1：copy 路径内存归属调查（只读，V1；v1-C3 降级改写）

- 撤销 v1 机制（"11 帧 RSS → 压到 3–4 帧省 90MB"无依据：`mediacodecdec_common.c:723–798` 证明 CPU 输出逐帧拷贝后立即归还 codec buffer；系统轮 11/15 个 output buffer 而 RSS 更低，证伪同一换算公式）。
- 调查内容：codec 内部分配池/客户端 AVFrame 池/gralloc 各占多少；哪个队列真正持有未归还资源；存在哪个可控参数、是否低于 codec/DPB/BufferQueue 最低需求；限流是否只减客户端内存。优先在 P1-A 之后重测（copy 不再是主路径则此项优先级自动下降）。
- 调查证实需改 wrapper → 原生 B 线独立立项，V2+全设备/路由矩阵（错误 facts 清理路径 `mediacodecdec.c:812–819` 的脆弱性有源码实据）。

### 独立线 2：打开中止受限重试（移出本方案，归 DV004 线，V2）

- v1-C4 的"facts 未发布=首帧前"定义被证伪：review 在返回完整 facts 前已登记 decoder 基线（`hdr_decoder_review.dart:427–472`），消失拒绝可发生在首次成功 review 前（`:375–380`），且 r1 日志（`:640` 完整 VideoParams → `:695–707` flush/卸载 → `:728–731` review 失败）不能证明"从未输出帧"——按 v1 定义会把契约必须拒的"已观测事实消失"洗成新 attempt 成功。
- 修正方向（DV004 线内设计）：结构化失败分类（区分"无完整 review 结果/尚未呈现/从未登记端点"），消失/反向附着/source 漂移/cleanup debt 恒终止；允许的新 attempt 须有旧 attempt 完整停止/清理屏障、新身份、晚到回调隔离、共享总预算、尊重 `failurePolicy.stop`；现有会话对 `HdrDecoderReviewFailure` 不重试是明确行为（`hdr_video_session.dart:809–833`），改变它不是性能优化的附带修改。若无证明安全的可重试类别，维持不重试。

## 3. 分期、定级与退出条件

| 阶段 | 工作包 | 审核级 | 退出条件 |
| --- | --- | --- | --- |
| P0 | 证据修正/基线冻结/根因观测/口径定义/API26+ 命中核实 | 采集 V0；因果判读 V1 | 差量与根因假设有实测数据；无差量配置不进入实施 |
| P1-A | embed 产品链可行性实验（boolean 默认） | **V1**（实验判读含因果与产品链等价性，不因"只是实验"降 V0） | 等价语义探针全过 + 门时序重放绿 + 功能限制清单定稿；不可行即停 |
| P1-B | 有证据的单变量配置/输出尺寸实验 | V1 | 实测差量成立才保留；最终画面/功能不退化；属性恢复闭合 |
| P2 | SDR presenter 准入与候选接入 | **V2** | 偏好/失败策略/功能准入/生命周期/HDR 矩阵全绿；HDR copy 边界零变化 |
| 独立线 1 | 内存归属调查 | V1 | 找到真实持有者与控制点；未找到则不进 wrapper 修改 |
| 独立线 2 | 重试设计 | V2（DV004 线） | 结构化分类+屏障+负例全绿；否则维持现状 |

终态验收（P2 落地后，指标以 P0 实测差量为准）：资源收敛用"lab 配对轮复测对照自身基线"表述（系统轮 GPU=0 使"系统 2 倍内"不可操作）；同 app 播放前后增量与绝对占用并报；present 节拍与 VO 计数双指标；颜色/亮度目视 + 缩放清晰度/功能等价评估；marble/LYA SDR 回归不回退；HDR 矩阵全绿。

## 4. 风险登记

1. **HDR baseLayerConvert 回归**（最高风险）：`_requiresMediacodecCopy` 三调用方含 HDR PlatformView 路径——任何收窄/旁路都是 HDR 矩阵回归。本方案以"完全不动该 helper"为红线。
2. embed 载体功能缺口（字幕/OSD/滤镜）：准入规则必须先于候选接入定义，消费者可按内容特征回退 Texture。
3. 门契约时序形状：值覆盖≠时序覆盖，P1-A 探针的完整附着时序必须重放现行门测试后才能谈立项。
4. HWC 合成层截图不可捕获（LG DV 既有教训）：颜色对照轮必须先验证截图通路，禁以黑图判黑屏。
5. 偏好排序交互：跨 topology 候选可能改变 `preferCopy` 语义（显式 copy 意图保留设计），P2 逐条核对。
6. `_setOwned` 空值契约（原值非空校验）与 native-DV 配对契约的误用风险：配置注入不得复用这两条通道的当前形态。
7. **sdrEmbed 默认启用的人群/证据/失败路径（2026-10-17 V2 复审登记）**：默认启用作用于**全 sdk16-25 人群而非单设备**；实机证据仅 LG H870DS/API24 且为受控显式 opt-in 形态（默认构建解析进同一 embed 执行路径但未作为默认构建实测），其它设备未验证；embed 观察失败由未改的复核门**终止会话**，不保证自动回退 copy（可分类依赖失败仍可重规划，门拒绝不重试）；默认路径不执行 mpv 侧 GL 功能为已接受取舍（用户决策）。V2 复审触发器延续：改 sdk 准入/unknown 策略、改门/重试/回退、改 preferCopy 优先权、引入自动 GL 检测或自动切载体、动 helper/HDR 边界、把 LG 证据扩大为全设备承诺。

## 5. Specialist 审核记录

- v1 审核（2026-10-17，独立 Specialist，对照 media-kit `b3dc1bf6` / mpv `9141961531` / FFmpeg `d4bb79394b`）：**BLOCK**。
- 四条 BLOCK 级修正：①embed（wid=Surface 直出，无 OES 绘制）与 surfacetexture（hwdec_surfacetexture.c 的 latch/FBO 路径）混写——C2 机制改写；②`_requiresMediacodecCopy` 实际作用域含 HDR PlatformView（baseLayerConvert），按 topology 收窄会破坏 HDR 路径——改为完全不动该 helper、embed 候选不经过它；③C3 "11 帧队列→省 90MB" 控制链被 `mediacodecdec_common.c:723–798` 证伪——降级为只读归属调查；④C4 "facts 未发布=首帧前"准入定义被 review 基线登记时序与 r1 日志证伪——移出本方案归 DV004。
- 其它采纳：C1 大部分措施已是现有默认（`real.dart:2674–2692`），收益降为待验证；embed 探针升 V1（等价语义标准）；§0 四处归因降级；`mediacodec` 值已被门 `startsWith` 覆盖（无须扩门）但时序须重放；embed 功能限制清单进入验收面；新增 P0（配置快照/输出尺寸/根因观测/口径/API26+ 命中核实）；新增候选（输出尺寸实验、SurfaceTexture importer 备选研究单列、API26+ direct 命中核实）。
- v2 状态：按上述修正全面重写，提交 Specialist 复核。
- v2 复核（2026-10-17，同一 Specialist）：**UNBLOCK**——四条 BLOCK 逐条核验解除（含调用点重查：`:377,533,570`）；可进入 P0/P1 工作包，**不构成** P2 产品接入、wrapper 修改或重试语义变更的批准。六条非阻断建议（present 指标层语义、HWC 观测判定、阈值冻结/AB 顺序、证据勘误、功能需求会话固定/运行中二分、逐像素对照语义）已吸收为 v2.1 对应条目；其中文字勘误（CPU 范围 20–21、RSS 原始 K 字段、`X→X_mediacodec` 拼写、SurfaceTexture 备选无工作包声明）在 v2.1 修正。
