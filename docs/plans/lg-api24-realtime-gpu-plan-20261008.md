# LG API24 原始 P8.4 实时全 GPU 播放执行计划
 
> 计划标识：20261008。状态：用户已接受技术路线，待下一会话分阶段实施、验证；本文不是实现完成记录或验收报告。
>
> 用户最新交付指令：“我接受该方案，但我需要换一个会话来执行，请将计划写入文件。”本次仅将已接受方案写成执行文档，不实施 OES importer，不运行测试、构建、设备操作，不修改设置，不提交或 push。
>
> 唯一 topic 上下文仍为 `/Users/wuweiwei1/src/media-kit/archives/conversations/lg-h870ds-hdr-demo-20261004.md`。任务事实源仍为 `/Users/wuweiwei1/src/media-kit/TASKS.md` 的“LG P8.4 色彩优化”项。本文只承载执行方案，不另建 handoff/conversation，不替代上述事实源。本次文档作者不修改 TASKS 或 conversation，由 Lead 补入口。
 
## 1. 阅读顺序、依据与状态标记
 
下一会话先读项目规则、任务入口、权威 conversation 顶部 `Current State`，再执行本文；不从旧 History 中恢复已撤销的结论。
 
1. `/Users/wuweiwei1/src/media-kit/AGENTS.md`。
2. `/Users/wuweiwei1/src/media-kit/AGENTS.local.md`。
3. `/Users/wuweiwei1/src/media-kit/TASKS.md` 中 LG P8.4 项。
4. `/Users/wuweiwei1/src/media-kit/archives/conversations/lg-h870ds-hdr-demo-20261004.md` 顶部 `Current State`。
5. 本文及阶段所需的定点证据、源码入口。
 
本文的状态含义：
 
- **已接受决策**：用户已明确选择的目标、范围和技术路线，不要求下一会话重新讨论是否走全 GPU 主线。
- **交接事实／历史观测**：来自用户提供材料及权威记录，只能归属于对应轮次；设备、工作树、磁盘、安装包等可变状态必须 fresh check。
- **实施计划**：尚待编写、接入或运行的工作，使用未勾选清单列出。
- **未验收**：没有相应运行证据或人工确认，不得因编译、日志或 setter 成功而填写通过。
- **拟新增／待核**：名称、文件位置或接口细节没有在本次文档落盘中逐项源码核验，不得据此宣称当前已经存在。
 
本次文档准备已只读核对 `AGENTS.local.md`、TASKS 对应项及权威 conversation 的 Current State。技术细节按用户提供的已接受方案整理；本次未开展源码大搜索、fresh 设备检查或二进制核验。本文中的旧哈希、PID、空间值均不因此成为当前观测。
 
## 2. 已接受目标与明确非目标
 
### 2.1 必须同时成立的目标
 
- 播放原始 P8.4 文件，输入为 **3840×1920、约 29.97 fps**，保持 MediaCodec 硬解原分辨率。
- 正常性能播放期间，**零解码像素 CPU 下载／再上传**；在 GPU 内完成导入、必要缩放和颜色处理。
- 正确完成 HLG 基层到 PQ 目标的颜色处理，不以标签冒充转换。
- 正确色彩与 4K 源约 30 fps 实时播放必须同时取得证据：真实活动管线、实际呈现证据，以及独立人工颜色／亮度／流畅性验收。
- 以固定可见 PlatformView 输出形态验收，不把输入 4K 描述成显示端 native 4K。
 
“零 CPU copy”只约束解码像素下载／再上传，不等于零 GPU 读写、零内部 GPU copy、零 CPU 控制开销。JNI、PTS 管理、资源调度、日志等控制面 CPU 工作仍然存在。
 
### 2.2 不得改变的边界
 
- 不预转码，不服务器转换，不用低分辨率替代播放素材，不另生成“优化版视频”作为达标依据。
- 停止扩展现有 GPU HDR 出口补丁；主线改为 **API24 全 GPU 导入／转换 + GPU 内缩小**。
- 只保留一次有证据、同真实 PQ 管线的 **full/full 对 limited/limited** 有界对照；不重开无限 dataspace、输出格式或厂商 hook 猜测矩阵。
- 用户所说的 `unlimited` 在本文中就是 **full range**，不是额外传输函数或第三种输出模式。
- 不把 SDR 作为最终替代终点。SDR 只可作为明确命名的诊断对照，不得静默回退后算 HDR 成功。
- 不做 fullscreen／旋转迁移，不借本任务修复全屏 Surface 生命周期专项。
- 不改变默认 P5 Dolby Vision、HDR10 direct、LYA 路线；生产默认 `auto` 不加载新 importer。
- 初期复用 FFmpeg 已有 MediaCodec 接口，不另写 Java 播放器、解码 loop，也不先修改 FFmpeg。
- 无 commit／push 授权；禁止 clean/reset、覆盖未知 dirty 或以清理空间为由删除未确认数据。
- 不承诺工期、速度提升比例或 4K30 一定成功。阶段门不通过时停在明确失败结论，不用替代验收掩盖。
 
## 3. 必须继承的事实纠正与未验收项
 
| 项目 | 可继承的结论 | 不得推导的结论 |
| --- | --- | --- |
| LG P5 nativeDV | 用户已确认 LG 上 P5 nativeDV 画面无问题 | 不能据此认定 LG P8.4 nativeDV 已通过 |
| P8.4 nativeDV | 完整 P8.4 nativeDV 人工通过属于 marble 设备；LG P8.4 nativeDV 的历史尝试不能视为完整成功 | 不把 marble 能力移植为 LG 能力声明 |
| LG P8.4 baseLayerDirect | LG 基层直出达到原生播放器水准：流畅，但颜色偏淡 | 不是本任务要求的正确 PQ 颜色终态 |
| CPU copy + libplacebo 的“颜色正常” | 此前可归属的颜色通过是 SDR 路线的人工验收 | 不把 SDR 颜色通过追认为 PQ 颜色通过 |
| R35b／R35c／R37／R38 | 实际为 `toneMapSdr`；保留用户观察，纠正路线归属 | “limited 已修好”“固定合成税”“色彩／性能必然二选一”等旧结论撤销 |
| 最新真实 PQ 重播 | ACTUAL 为 `baseLayerConvert/PQ/platformView/gpu-next/mediacodec-copy/pq-itu`，无 SDR 回退；用户反馈“色彩淡且帧率不高” | 不声称颜色或流畅通过；亮度未单独评价；无实际呈现计数，不能填数值 FPS |
| 移除 copy 的收益 | 是本计划要检验的架构方向 | 不承诺移除 copy 必然修好颜色，不预设 copy 是唯一瓶颈 |
| full 与 limited | 必须在真实同管线、匹配像素 range 与输出标签后比较 | 旧“limited 慢、full 快”混入 SDR，不能作为稳定因果或性能常数 |
| libplacebo OES | 普通 libplacebo 已支持 external OES | 不因需要中间 2D 纹理而声称 libplacebo 缺 OES 支持 |
| 计数与呈现 | latch、swap、媒体时钟等可辅助定位阶段 | `vfps`、零 decoder drops、mpv `frame-count` 都不是实际呈现 FPS；`frame-count` 可能来自 duration 估计 |
 
当前权威材料记录了真实 PQ 路线成立和人工失败，但未证明最终 buffer／panel 的完整 dataspace 状态；setter 成功、请求值、属性读回与面板显示各自独立。不得把缺失的 readback 填成成功。
 
## 4. 固定输出与 Session 契约
 
### 4.1 现有可见输出保持冻结
 
保留已经存在的可见 PlatformView output surface 及受限 visual278 实验路线：
 
- 精确 LG 固件、API24、arm64 与 hook／ABI 门保持原有范围，不放宽为所有 LG 或所有 API24。
- visual278 的既有实验接受不变；历史 EGL 枚举中它是 10/10/10/2 WINDOW、NON_CONFORMANT 配置，不把实验接受升级为通用平台保证。
- 保留默认 visual43 及既有精确实验分支的边界；不为了 importer 绕过 window format、capability 或绑定检查。
- 单 Session、单次 `open`、唯一可见 output owner；失败或 destroy 后 owner 授权退休，不能在下一代复用。
- 继续区分 setter accepted、query／perform 结果、可用 readback 与最终显示证据。
- 不创建提前 fallback Texture，不让 UI getter 抢先建立与 Session 竞争的输出；继承现有 Session-only 实验 UI 约束。
 
**内部 decoder Surface 不是第二显示窗口。** 它只连接 MediaCodec 输出和 SurfaceTexture，不接收 display owner 授权，不挂可见 View，不被当作第二个 PlatformView 或第二个 display output，也不应消费可见输出的 visual278 owner token。
 
### 4.2 明确 opt-in 与 fail-closed
 
拟议配置形态为 `hwdec=mediacodec` 加一个明确的新 interop（拟名 `surfacetexture`，尚未实现，不是当前可用选项承诺）。实施时以真实注册名和候选能力为准。
 
- 在 open 前完成实验准入、owned options 快照／设置／读回；任何失败、取消和关闭必须恢复原值，不能泄漏到后续 Session。
- 新候选的实际活动 importer 必须为 SurfaceTexture 路径，不能仍报告 `mediacodec-copy`。
- 选项已设置、`hwdec-interop` 列表含名称、库内存在字符串，都不能替代 active importer 的运行证据。
- 必须关联 native 候选版本、活动 importer 实例、opaque frame 输入、输出纹理及本次 Session／source generation。缺失关键证据即拒绝验收；不能先播放后用预测值补 ACTUAL。
- 新候选禁止 software／copy／SDR fallback。显式 copy 或 SDR 诊断是独立对照 Session，不是候选失败后的退路。
- 既有 output slot key 不包含 interop，故每个变体使用 **fresh Session**，不得在 live Session 内切换 interop、range 或目标参数冒充独立试验。
- 每个 fresh Session 使用自己的合法 owner；“同输出契约”不等于跨 Session 强行复用同一 owner 或已退休 Surface 身份。
 
## 5. 技术架构与原生不变量
 
### 5.1 最小复用链
 
计划使用以下链路，不替换播放器核心：
 
```text
原始 P8.4 文件
  → mpv 既有 demux／decode 调度
  → FFmpeg MediaCodec 硬解，AVMediaCodecDeviceContext.surface
  → opaque MEDIACODEC frame／原始 PTS／既有 buffer release 语义
  → 内部 Java Surface + SurfaceTexture（API24，经 JNI）
  → mpv 既有 GL context 线程 updateTexImage／transform／采样
  → 稳定帧 lease：GPU 2D 纹理或等价的安全融合产物
  → GPU 内缩小与 libplacebo 颜色处理
  → 冻结的可见 PlatformView output surface
  → 系统 compositor／面板（独立呈现与人验）
```
 
- AHardwareBuffer 路径需要 API26；NDK SurfaceTexture 接口需要 API28，不能拿来绕过 API24 限制。
- `hwdec_aimagereader.c` 只用作 API26 路线参考，不能通过放宽其 API gate 获得 API24 支持。
- API24 使用 Java `SurfaceTexture` 经 JNI；callback 只通知帧可用／唤醒，不能在 callback 线程执行 GL。
- GL 操作在 mpv 已有、正确 current 的 GL context 线程执行，不另造不受现有 VO 调度约束的渲染线程。
- libplacebo 的 external OES 能力可复用。中间 2D 纹理的价值是稳定帧 lease、落实 transform／crop 和限定处理尺寸，不是补库的采样能力缺口。
- 独立 OES→2D pass 不预设为永久结构；允许目标尺寸采样与颜色转换融合，但稳定 lease 和多 retained frame 不可被覆盖的约束不能省略。
 
### 5.2 PTS、release、纹理与 GPU 同步
 
以下各项是阶段准入条件，不是后续可选优化：
 
1. **每个 opaque buffer 只 release 一次。** 正常渲染、丢弃、flush、初始化失败、取消、异常退出都必须进入明确且互斥的 release 分支。不能在 importer 和原有 frame 释放路径各 release 一次。
2. **媒体 PTS 与单调时钟分域。** 不把 media PTS 直接传给以 monotonic 时间为基准的 `render_at_time`。复用现有 release／调度语义，若使用定时释放，必须先证明时间基转换和时钟域正确。
3. **SurfaceTexture 的“最新帧”不是传入对象的自动同义词。** 建立 release 请求、SurfaceTexture timestamp、source identity、generation 与原始 source PTS 的关联，验证单位和映射。不能仅按 callback 次数把 PTS 顺序塞给 latch。
4. **redraw 不制造新源帧。** 重绘沿用同一 source identity／generation／PTS；发生跳过须记 skip，发生重复须记 duplicate，不能把新 latch 的像素标为旧 PTS。
5. **稳定且有界的纹理 lease。** 设计池上界、占用／归还／discard 规则、fence 及背压策略。gpu-next 同时 retained 的多个帧必须对应不会被下一次 latch／写入覆盖的纹理内容。
6. **不每帧 `glFinish`。** 使用正确的同 context 顺序、必要 fence 与资源复用约束；明确区分 OES mutable 内容、GPU 采样完成和下游 lease 退休。扩展不可用时不能靠无限等待或取消同步保证来假通过。
7. **资源上界可测。** decoder queue、待 latch 队列、纹理池、retained frame 与未完成 fence 均有界；队列满时显式背压或显式记录丢帧，不隐式 latest-only 吞帧后声称 1:1。
8. **crop／transform 正确。** 解码 allocation、有效 crop、SurfaceTexture transform、图像方向和显示 crop 必须一致。工作尺寸改变后，同步 gpu-next 的原图 crop 坐标及尺度，不能只改 texture width／height。
9. **代际屏障。** seek、flush、late callback、取消、退出、初始化失败均需要 source／codec／SurfaceTexture generation 屏障；必要时重建内部 decoder Surface 并与 codec 协调。旧内容无法可靠隔离时失败，不能发布 stale 帧。
10. **JNI 生命周期可审查。** 从 app class loader 显式初始化 Java 类／方法绑定，妥善管理 JNI global refs、线程 attach／detach 与 bridge 生命周期；不在 native VO 线程盲目 `FindClass`。
11. **不占用已有私有字段。** 不借 `mp_image.priv` 的现有用途塞新的跨线程状态；按真实扩展点设计 frame lease／interop 私有对象，绑定关系在源码审查中明确。
 
### 5.3 颜色语义与精度
 
- OES 采样可能已经由驱动完成 YUV→RGB、limited 展开及精度处理，必须测试实际行为。
- 导入后按实际 **RGB** 语义声明 representation，不把已转换的 RGB 再当 YUV 做第二次矩阵；HLG transfer 的 inverse 只在正确位置执行一次。
- range affine 变换与 HLG→PQ 传输函数处理不是一回事。limited→full 是乘加，成本比 HLG→PQ 低，可融合到已有 GPU shader，无需专门 CPU pass 或新增独立 pass。
- 复用 `video-output-levels` 的已有 range 能力；必须先确认 OES 是否已经做过 limited 展开，避免重复 expansion／compression。
- 不能只把 HLG 标签改为 PQ，也不能以 range 变换代替 transfer／OOTF。
- 不移植 Kirin P5 的 `1023/1020` 补偿；那是另一设备／格式／管线的已知行为，不是 LG SurfaceTexture 的通用规则。
- Main10 解码加 10-bit 输出 surface 不保证中间链 10-bit。应检验 shader 浮点与 sampler 的实际 highp、驱动 OES 精度、FBO 格式及处理结果。
- encoded HLG 中间纹理可以评估 `RGB10_A2`；linear HDR 或需要 headroom 的中间纹理优先评估 `RGBA16F`。实际选择取决于域、范围与 context 能力，不能假定 UNORM 格式能保存超出范围的 headroom。
- 对每种实际选用格式，在该 GL context 验证 renderability、filterability 和 framebuffer completeness；不静默降为 RGBA8。
- linear FBO 不能继续标为 HLG encoded；颜色元数据必须随着数学域变化而更新。
 
## 6. 环境、素材、证据与构建溯源
 
### 6.1 本机及设备交接快照
 
| 项目 | 交接信息 | 接手要求 |
| --- | --- | --- |
| 主代码库 | `/Users/wuweiwei1/src/media-kit` | 保护全部未知 dirty |
| mpv | `/Users/wuweiwei1/src/mpv`；交接基线 `d24c59905b` 加大量 dirty | commit 不代表当前完整源码，必须锁定实际源码清单／hash |
| FFmpeg | `/Users/wuweiwei1/src/FFmpeg`；交接版本 `00d1ffc172` | fresh 核验实际构建输入及链接产物；初期不改 FFmpeg |
| libplacebo | 本地源码副本与 build repo 内副本并非天然同一份 | 由实际 manifest 确定源码、revision、dirty、构建目录和链接来源；本文不猜部署副本 |
| LG serial | `LGH870DS42e27764` | 每次设备命令显式绑定并核对真实设备 |
| 固件 fingerprint | `lge/lucye_global_com/lucye:7.0/NRD90U/172921900e77a:user/release-keys` | 精确匹配，API24／arm64／hook 门不放宽 |
| 最后播放观测 | PID `26640` 曾保持播放供用户人验 | 不是当前 PID；先 query，不盲 force-stop 或打断现有播放 |
| 磁盘 | 上次约 31 GiB 可用 | 每次构建前 fresh check；不足则停止受影响步骤，不删未知文件 |
| Java | `/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home` | 按 AGENTS.local 用临时 `JAVA_HOME`；不改全局配置 |
| Flutter | `/opt/homebrew/share/flutter/bin/flutter` | 显式使用此 SDK，不使用 PATH 中另一套 SDK |
 
后续若需唤醒设备，只在已连接且无受保护锁屏时按 `AGENTS.local.md` 的规则操作并验证状态；不绕过密码／生物识别锁。不因本文而获得修改亮度、刷新率、系统 logger、开发者设置或其它持久化设置的授权。
 
### 6.2 固定原始播放素材
 
- 主机文件：`/Users/wuweiwei1/src/media-kit-build/lg-api24/p84-direct-run-r27b/p84-readback.mp4`。
- 设备文件：`/data/local/tmp/media-kit-p84-7626cac2.mp4`。
- 字节数：`1232790317`。
- SHA-256：`7626cac28819ffd1377a712b56c7cc4bbf8677f5db4b39fb0c83f92e58d74443`。
 
下一会话按既有可信工具 fresh 核验字节及全文件 hash，不用文件名、size 或历史成功代替。所有正式播放变体使用此原始文件；测试色块与数学参考用于诊断，不制作预转换播放文件代替原始素材。
 
### 6.3 旧 copy 基线身份
 
以下仅标识交接时的旧 copy 基线，不是新 OES 实现，也不是下一候选的准入 pins：
 
| 工件 | SHA-256 |
| --- | --- |
| APK | `e63560e27509fcf84de30a9fd49cb0d618990973a0f6938afaa6c8b44d846609` |
| native JAR | `47ecef57aa43b9d7d4ae9badab4c5c0c3ed991dbe1cc97acfcf6d03ef4881349` |
| libmpv | `ec8fb3368814cdf7cf017df228e70c778a91321a1add807bb59019e0b22a131a` |
 
历史安装信息必须 fresh readback 后才能描述为当前安装状态。同版本号不意味着同二进制；不得拿旧包结果冒充新包验收。
 
### 6.4 构建和 native candidate 边界
 
已知 builder 入口：
 
`/Users/wuweiwei1/src/media-kit-build/lg-api24/lg-visual278-session-only-20261008/build-release.py`
 
旧工具／candidate 定位：用户给定 `n4-session-device-tools-r22-bound/native-candidate.json` 和 `n4_contract.py`。按已有 lg-api24 根拼接的待核入口为：
 
- `/Users/wuweiwei1/src/media-kit-build/lg-api24/n4-session-device-tools-r22-bound/native-candidate.json`（完整位置待核）。
- `/Users/wuweiwei1/src/media-kit-build/lg-api24/n4-session-device-tools-r22-bound/n4_contract.py`（完整位置待核）。
 
执行要求：
 
- 新 importer 必须建立新的 native candidate、provenance 与 pins；保留旧 candidate 及旧审批，不覆盖成“同一候选的新内容”。
- 旧 manifest／hash／approval 不适用于新 native。更新门禁绑定而非关闭核验。
- 记录 mpv、FFmpeg、libplacebo、Java bridge、media-kit 实际源码／补丁与工具链来源，不能仅记各仓 HEAD。
- build repo 的旧 FFmpeg depinfo pin 不一定等于实际部署来源，必须沿实际链接和嵌入产物核验。
- 构建时显式注入 `ORG_GRADLE_PROJECT_mediaKitLocalArm64Jar`；防止回退到 Maven／错误 JAR。
- 每个候选核对 fresh APK embedded lib、构建前后 source hash／manifest、安装后整 APK／native readback；相同版本标签不能替代字节身份。
- 构建／测试共享状态串行占用，不与其它 writer／验证者并发改变输入。
- 初期不修改 FFmpeg；若真实接口限制导致必须改 FFmpeg，先记录具体阻断与证据，交 Lead 明确范围，不静默扩大本计划。
 
### 6.5 权威证据入口及存放位置
 
- 精选基线报告：`/Users/wuweiwei1/src/media-kit-experiments/artifacts/lg-hdr-20261004/lg-visual278-session-only-20261008/REPORT.txt`。
- EGL probe：`/Users/wuweiwei1/src/media-kit-experiments/artifacts/lg-hdr-20261004/lg-egl-format-investigation-20261008/`。
- 真实 PQ 人验重播原始证据：`/Users/wuweiwei1/src/media-kit-build/lg-api24/lg-pq-human-replay-20261008-113634/`。
- 原始日志、binary、截图、设备敏感身份及大文件放 `/Users/wuweiwei1/src/media-kit-build/` 下对应独立轮次目录。
- 精选匿名证据放 `/Users/wuweiwei1/src/media-kit-experiments/`；不得把 raw token、native 地址或其它敏感信息推入公开材料。当前也没有任何 push 授权。
- 实施推进和关键结论由 Lead 更新既有 TASKS／conversation；不新增第二个 topic 上下文。
 
## 7. 定点源码与测试入口
 
这些是下一会话的定点导航，不要求本次落盘扩展搜索。标为拟新增的项均尚未实现；未给完整文件名的模块应在对应目录定点确认，不能把本文的描述名当作现成 API。
 
| 区域 | 路径／定位 | 计划用途与限制 |
| --- | --- | --- |
| API26 参考 | `/Users/wuweiwei1/src/mpv/video/out/hwdec/hwdec_aimagereader.c` | 参考 opaque frame／interop／资源管理；不放宽其 API gate |
| API24 importer | `/Users/wuweiwei1/src/mpv/video/out/hwdec/hwdec_surfacetexture.c`（拟新增） | 显式 opt-in importer、bridge、latch、纹理 lease、代际屏障 |
| hwdec 注册 | `/Users/wuweiwei1/src/mpv/video/out/gpu/hwdec.c`、`/Users/wuweiwei1/src/mpv/video/out/gpu/hwdec.h` | 能力及注册，确保默认 auto 不加载新 importer |
| 构建入口 | `/Users/wuweiwei1/src/mpv/meson.build` | API24 可用依赖和新文件的受限构建注册 |
| JNI | `/Users/wuweiwei1/src/mpv/misc/jni.c` | 与 app class loader 的显式绑定和已有 JNI 工具复用 |
| gpu-next 生命周期 | `/Users/wuweiwei1/src/mpv/video/out/vo_gpu_next.c` | acquire／release／discard、`VOCTRL_RESET`、retained frame 和 crop 坐标 |
| FFmpeg 既有接口 | `/Users/wuweiwei1/src/FFmpeg` 内 MediaCodec 相关接口，具体文件按调用链待核 | `AVMediaCodecDeviceContext.surface`、opaque MEDIACODEC buffers、PTS／release；初期只读复用 |
| libplacebo GL | 实际 manifest 锁定的 libplacebo 源码根内 `opengl.h`、`gpu_tex.c`（完整位置待核） | 已有 external OES 支持、纹理格式能力与导入语义 |
| libplacebo 缩放／颜色 | 同一真实源码根内 `renderer.c`、`colorspace.c`、`shaders/colorspace.c`（完整位置待核） | scaler、pass 次序、range、transfer／OOTF；先测已存在能力 |
| Java bridge | `/Users/wuweiwei1/src/media-kit/media_kit_video` 平台代码中 `MediaCodecSurfaceTextureBridge.java`（拟新增；包目录与 native class 绑定待核） | Java SurfaceTexture 生命周期、callback 通知、class loader 初始化；不是第二播放器 |
| Dart／平台契约 | `/Users/wuweiwei1/src/media-kit/media_kit_video` 内 hdr_route／backend／session／realizer／output report 模块（完整文件名待核） | opt-in 能力、owned options、严格 route、输出身份及 active evidence |
| Lab | `/Users/wuweiwei1/src/media-kit` 内 hdr_lab 的 lab common 和 `android_hdr_convert_experiment`（完整目录待核） | 新建独立 SurfaceTexture experiment 类；不放宽旧 copy 验证器 |
| 测试 | hdr backend options／review／session、size、lab `android_hdr_convert_experiment`、native gate／ledger 测试（完整文件名待核） | 新路由与默认隔离、恢复、尺寸、生命周期及证据语义不回归 |
 
按 `agent-team-routing` 分派独立工作包，文件单一 writer；共享构建／设备验证串行。审核等级按实际改动确定：涉及 output 授权、native 生命周期等高影响不变量时执行相应 V2 独审；不能因“跨模块”一词自动升级，也不能用作者自审替代必需的独审。工具或角色不可用时如实停止受影响验收，不虚构审核完成。
 
## 8. 分阶段实施与 stage gate
 
总原则：上一阶段的必要门未通过，不进入后续长时验证。短诊断用于关闭明确问题，不无限扩展参数或设备实验。阶段结果必须绑定源码、native candidate、APK、Session、source generation 与观测窗口。
 
### 阶段 0：冻结基线、现有能力和输出契约
 
**目的**：在改 importer 前知道真实输入、真实 pass、真实目标和真实旧包；避免把已有设置当新优化或把错路线比较当因果。
 
- [ ] 按第 1 节读取最新上下文，核对工作树及可用工具；记录未知 dirty，不重置、不覆盖。
- [ ] fresh 核对素材、磁盘、设备身份和当前播放状态；先 query，不能把 PID26640 或 31 GiB 当当前事实。
- [ ] 核定 mpv／FFmpeg／libplacebo 实际构建副本、版本和 dirty 来源；冻结旧 copy 基线及输出相关代码 hash／路由契约。
- [ ] 记录 input format、decoder 真实格式／bit depth／allocation／crop，不能只写 HEVC Main10。
- [ ] 解析并记录 `video-target-params` 的实际 target peak、reference white、transfer／primaries／range／OOTF 相关结果；区分请求选项、解析值与活动行为。
- [ ] 保存 current options 和 owned options 原值／恢复协议，包含 renderer、hwdec、interop、output levels、缩放、peak 配置及输出实验门。
- [ ] 记录每个实际 pass 的输入／输出尺寸、格式、顺序及可用 timing。当前已有 bilinear 和 `hdr-compute-peak=no`，不能再把启用它们列为新优化。
- [ ] 确认当前 libplacebo 已有缩放先于颜色处理／融合的实际路径；不能假定旧链路对全部 4K 像素执行完整颜色转换。
- [ ] 分开记录 decoder allocation／crop、OES（新路径待填）、working、each pass、EGL buffer、viewport、SF rectangle；旧 final 已为 1440×720，不能把 1920 cap 直接当性能收益。
- [ ] 冻结可见 PlatformView／visual278／firmware／hook／owner 契约，标明已有 readback 缺口，计划只补 importer 所需证据，不扩输出补丁。
- [ ] 固定对照的源 PTS 段、renderer、crop、目标颜色、目标尺寸和峰值参数；不同颜色目标不能直接用来解释 importer 的性能／色差。
- [ ] 定义 active importer telemetry 与新 candidate provenance 的字段，明确 option 或能力列表不够。
 
**阶段产出**：可追溯基线、实际 pass／尺寸记录、固定输出契约、新候选准入定义及仍缺证据的清单。基线仍是 copy，不能称全 GPU 已完成。
 
**通过门**：源码与工件身份可追溯，旧行为与拟改行为区分清楚；比较条件可冻结，fallback 与 active evidence 判据明确。
 
**停止条件**：实际构建来源不明、无法保护未知修改、输出契约不一致或必要环境输入缺失。停止受影响工作，由 Lead 在既有任务上下文记录 blocked，不绕过门禁。
 
### 阶段 1：最小 API24 import PoC 与精度门
 
**目的**：先证实真实 mpv 解码接口能在 API24 通过 SurfaceTexture 安全、正确导入，不先搭完所有实验 UI 再发现基础精度／PTS 不成立。
 
- [ ] 实现最小显式 opt-in hwdec importer，复用 FFmpeg `AVMediaCodecDeviceContext.surface`、opaque frame／PTS／release，不编写独立解码 loop。
- [ ] 实现拟议 Java bridge 与显式 class-loader 初始化；callback 只通知，GL 线程完成 latch／transform／采样。
- [ ] 增加真实 active importer／candidate 版本／frame identity 证据；默认 auto 不加载它，实验缺证 fail-closed。
- [ ] 先证 opaque→SurfaceTexture 的 release-once、timestamp 与 source identity／generation 映射，再允许帧进入 gpu-next。
- [ ] 验证 crop、方向、SurfaceTexture transform、实际 OES 格式语义以及 shader 浮点／sampler highp。
- [ ] 建立最小有界稳定纹理池及 lease／fence／discard；多 retained frame 不共享会被覆盖的内容，不逐帧 `glFinish`。
- [ ] 验证实际 FBO 格式的 renderability／filterability 和输出精度，无 silent RGBA8 fallback；Main10 + 10-bit output 不单独作为证明。
- [ ] 用灰阶、饱和色、near-black 和 10-bit steps 与数学参考检查 OES 矩阵、range、量化及 transfer 域；测试色块／shader 参考不是预转换播放素材。
- [ ] 在相同原始源、PTS 段、SDR 目标、renderer、crop、尺寸、峰值配置下，做短的 **copy SDR 对 OES SDR** 诊断，定位新增 importer 误差。记录 copy 的 NV12 为 8-bit，不是 P010，也不能把它当 10-bit 精度真值。
- [ ] 如需像素数值读回，仅在显式诊断模式做小区域 readback，记录其启用状态；性能播放必须关闭，不允许全帧解码下载／再上传。
- [ ] 如 standard OES 明确出现无法接受的矩阵或精度问题，只做一次有边界的 `GL_EXT_YUV_target` 能力／行为 probe；记录是否支持、实际结果和原问题是否关闭。
- [ ] 对初始化失败、release 分支、取消、late callback 和代际切换做最小负向验证；不能只测首帧成功。
 
**阶段产出**：API24 importer PoC、实际活动证明、PTS／lease／资源上界证据、SDR 同目标诊断和精度结果；必要时一次 YUV-target probe 的结论。
 
**通过门**：真实原始硬解帧经新 importer 进入 GPU，无软件／copy／SDR 隐性 fallback；基础精度、transform、PTS、release／lease 可证，正常播放无像素 CPU 往返。
 
**停止条件**：standard OES 失败且一次 bounded YUV-target probe 仍不能满足精度／矩阵要求，或无法可靠关联帧身份、保证资源生命周期。此时停止，不盲目集成后续优化，不通过放宽 API26 gate、RGBA8 降级或强行换 FFmpeg 来掩盖。
 
**验收限定**：SDR 对照仅是诊断，不是 HDR 目标通过；PoC 首帧或短播也不是持续 4K30 验收。
 
### 阶段 2：GPU 内缩小与 pass／质量对照
 
**目的**：降低真实 GPU 工作量，同时保留原始 4K 解码输入和可接受质量；以 actual pass 与 timing 决定结构，不预设多一个 pass 必然更快。
 
计划对照两类实现：
 
- **可审查基线**：OES → encoded HLG 小 FBO → 现有 libplacebo 颜色处理／输出。
- **融合候选**：目标尺寸采样与颜色转换融合，避免不必要的中间读写／pass；仍满足稳定帧 lease、retained frame 及域标注不变量。
 
- [ ] 保持 decoder 输入／allocation 为原始 3840×1920，不用降低解码分辨率或替代素材达标。
- [ ] 先比较 working 1920×960 与 1440×720；用 3840×1920 working 做短 control，固定 final 布局 1440×720。
- [ ] 仅在上述候选仍需权衡且质量可明确评估时考虑 960×480；记录画质代价，不能静默采用较小尺寸后宣称同等画质。
- [ ] 每个变体 fresh Session，冻结 source PTS 段、renderer、输出 target、crop、峰值、显示布局与温度条件。
- [ ] 逐项记录 decoder allocation／crop、OES 尺寸／transform、working 尺寸、每个 pass 尺寸／格式、EGL／viewport／SF rectangle。
- [ ] 同步 gpu-next 原图 crop 坐标与工作尺寸变化；加入比例、边缘、非整倍数缩放和有效 crop 的验证。
- [ ] 核对 encoded HLG 平均与 linear 平均的差异，不把 encoded 域 bilinear 当成正确的线性光面积滤波。
- [ ] 2:1 bilinear 可近似 box，但 3840→1440 不是充分的 area filter；对运动细节、细线、边缘、高光、暗部和混叠做质量观察。
- [ ] 依据数据域选择 RGB10_A2／RGBA16F 等实际验证可用格式；linear FBO 不再 tag HLG encoded，不为缩小丢失所需 headroom。
- [ ] 检查 libplacebo 当前是否本已在较小尺寸执行主要颜色 pass；用实际 pass／GPU timing 判断收益，不按像素数推算“预计四倍”。
- [ ] 比较独立小 FBO 与融合候选的总耗时、同步等待、GPU 读写和质量；融合更快且安全时不强制增加独立 FBO pass。
 
**阶段产出**：固定显示布局下的工作尺寸／pass 对照、实际格式能力、GPU 耗时与质量证据，选出后续 PQ 颜色／性能阶段的候选。
 
**通过门**：没有 CPU 像素往返、无 crop／transform 错误、无错误颜色域标记，实际 GPU 工作量与表现有证据，质量代价透明。
 
**停止条件**：只能通过未验证 RGBA8 fallback、错误 crop、错误 transfer 域或不可接受画质获得速度；不把这些结果并入成功候选。若无收益，如实记录，而不是继续增加无依据 pass。
 
### 阶段 3：真实 PQ full／limited 与颜色验收
 
**目的**：在已成立的新 GPU importer 管线上完成真实匹配 range 对照，独立判断颜色是否正确；不再利用历史 SDR 错归属作结论。
 
#### 3.1 一次匹配 range 对照
 
仅改变既有输出 range 组合，每个变体 fresh Session：
 
| 变体 | 实际输出像素 range | 既有输出标签 | 其它条件 |
| --- | --- | --- | --- |
| Full | full | `pq`／full | source、PTS、renderer、crop、尺寸、peak／reference-white／OOTF 与 Limited 相同 |
| Limited | limited | `pq-itu`／limited | 与 Full 使用同一新 importer 和同一冻结显示契约 |
 
- [ ] 全程实际目标为 PQ；记录 source 为 HLG、转换结果为 PQ、range 与 label 匹配，不允许 full 像素挂 limited label 或相反。
- [ ] 复用 `video-output-levels`／libplacebo 既有 GPU range 能力；range affine 融合到现有处理，不另加 CPU pass，也不因 range 单独增加 pass。
- [ ] 再核对 OES 是否已进行 limited 展开；不要在 RGB 导入后重复矩阵、range expansion 或 HLG inverse。
- [ ] 采集两变体的真实 active path、resolved target、GPU 耗时、可用呈现证据和人工颜色／亮度／流畅性反馈。
- [ ] 只有 full 同时颜色正常且性能更好，才采用 full；否则不加饱和度“凑颜色”，也不把 full 天然更快写成事实。
- [ ] 比较无效时明确标明原因，不拿缺 route／缺身份／混入 SDR 的一轮填入结果，不扩大成无限输出补丁尝试。
 
#### 3.2 同目标 copy／OES 诊断矩阵
 
为分离 importer 的误差与目标／显示端问题，保留以下诊断矩阵。矩阵的每一行必须固定相同目标和参数，SDR 与 PQ 两行不能直接相减归因；copy 仅是显式对照，不是候选 fallback。
 
| 目标 | copy 诊断 | OES 诊断 | 用途 |
| --- | --- | --- | --- |
| 固定 SDR | 已知 copy 路线，NV12 8-bit | 新 importer，相同 SDR target | 隔离导入、range、matrix 与精度新增误差；不验收 HDR |
| 固定 PQ | 真实 copy PQ，不用历史 SDR 冒充 | 新 importer，相同 PQ target／range | 区分导入差异和共同显示问题 |
 
- [ ] 优先复用参数和来源严格一致的既有诊断结果；不能一致时只补必要短对照，不制造全面重复试验。
- [ ] 明确 copy NV12 的 8-bit 限制，数学参考／测试色块用于判断精度，不能以两条路线同样失真作为正确性证明。
- [ ] 按实际 resolved peak／reference-white／OOTF 做有界核对；如确有必要，可比较 auto 与 1000 nit 参考配置，记录真实解析结果，不做无边界参数扫。
- [ ] 不能从旧 `target-peak` 改动“看起来无变化”推导全部 peak／OOTF 假设都已排除。
- [ ] shader 数值正确而冻结 PQ 显示仍淡时，停止该 HDR 候选并记录限制；不重开无限 output 补丁，也不擅自把最终目标改为 SDR。
 
**阶段产出**：真实 PQ 匹配 full／limited 对照、同目标 copy／OES 诊断、resolved target 证据及分项人工结论。
 
**通过门**：最终候选的真实颜色路线、数值处理与人工颜色／亮度接受有证据；随后仍需阶段 4 的持续性能及生命周期验收。
 
**停止条件**：颜色仍不通过、输出标签与像素不符、route／readback 缺口被虚构为成功，或只能靠饱和度补偿掩盖未明问题。颜色未过不能只凭性能继续宣布方案成功。
 
### 阶段 4：持续性能、实际呈现与生命周期
 
**目的**：证明原始 4K 源在选定工作／显示分辨率下持续近 1:1 播放，且资源与代际安全；不能用内部推进代替上屏帧率。
 
#### 4.1 先短 gate，再持续冷／热窗口
 
- [ ] 先做短 gate，确认候选身份、active importer、GPU 格式、无 fallback、无 readback、无 stale、队列有界和基本画面正常。
- [ ] 短 gate 通过后执行数分钟持续观察；冷态和热态分开记录，不把历史热机数据与当前冷机数据直接相减。
- [ ] 记录温度／可得调频状态和环境条件，但不通过修改频率、刷新率或系统设置达标。
- [ ] 分离 decode、release／latch、prepass、convert、swap wait 的耗时。CPU wall-time 不冒充 GPU 执行时间。
- [ ] GPU timer query 仅使用 context 实际支持的能力；剔除 disjoint 区间，并记录缺失／无效样本，不把它们记作零耗时。
- [ ] 以唯一 source PTS + source identity + generation 统计 decoded／released／latched／rendered／submitted，并另列 duplicates、skips、队列深度、纹理池／内存峰值及 A/V 漂移。
- [ ] 统计明确说明同一帧重复显示、重绘和真正新源帧的差别；不能靠 hidden drop 保媒体时钟后报 30 fps。
- [ ] 对每个窗口输出持续时长、有效样本、唯一源帧数、间隔分布／长停顿、丢弃／重复及测量方法；结果与候选工件绑定。
 
#### 4.2 实际呈现证据的优先级与止损
 
1. **SurfaceFlinger 短试**：仅做有界短试并确认目标 layer 关联。旧轮多次只得到 refresh period、没有有效 present timestamp，已知无效时不重复长 polling。名字相同的 UI／video 层不能只凭名称当成同一 owner。
2. **可关联的 EGL／compositor 证据**：若实际支持 EGL frame timestamps 扩展，或能取得与本次 layer／buffer／source frame 关联的 compositor trace，则记录支持能力、时间戳语义、关联方法及缺失值。不能把 latch timestamp 改称 present timestamp。
3. **外部相机后备**：上述方法不可用时，使用 120／240 fps 外部相机，配合渲染时嵌入的实际 source PTS／frame identity 标识，计数 unique displayed 帧。标识属于本次 GPU 诊断叠加，不预转码原文件；同一 source 帧 redraw 不增加 ID。记录相机采样、读码方法、不可读区间及叠加开销。
4. **仍缺工具或关联证据**：如实标“实际呈现 FPS 未验收”。不能以 swap 次数、媒体 clock、`estimated-vf-fps`、零 decoder drops、mpv `frame-count` 或只有 latch 的日志替代。
 
这里的“实际呈现”要求能够把显示更新关联到唯一源帧，而不只是有 buffer 被提交。相机／截图不能替代用户光学亮度和颜色判断；普通截图对 HWC overlay 失真也不能直接判定手机黑屏或停帧。
 
#### 4.3 生命周期矩阵
 
- [ ] 正常暂停／恢复：无新 source 时 redraw 保持同一身份；恢复后无旧纹理覆盖新帧。
- [ ] seek：旧 source generation 被屏障隔离，目标段首帧 PTS／像素关联可靠。
- [ ] flush／codec 重新同步：opaque buffer、pending callback、SurfaceTexture 队列与 lease 不跨代污染；必要内部 decoder Surface 重建与 codec 协调。
- [ ] late callback：过期通知被明确忽略或排空，不发布 stale，不访问已销毁 Java／GL 对象。
- [ ] 初始化／中途失败及取消：保留原错误、拒绝 fallback，buffer release-once，owned options 恢复。
- [ ] EOS，或记录明确时限与原因的 bounded stop：不能把未到 EOS 伪记为全片通过。
- [ ] Back／销毁：可见输出 owner revoke／retire、内部 decoder Surface／SurfaceTexture 释放、retained lease／fence 清理、Session／Player 退出均有对应证据。
- [ ] 内部 Surface 释放和可见 output ACK 分开记录；Java release ACK 不等于 SurfaceFlinger 内存完全回收。
- [ ] 多次 fresh Session 重入后无纹理／JNI 引用／队列累计增长；不进行本任务范围外的 fullscreen／旋转迁移。
 
**阶段产出**：冷／热持续窗口、唯一源帧流水账、实际呈现测量及误差／缺口、生命周期结果、人工终验。
 
**最终通过门**：在明确工作尺寸／显示尺寸下，原始约 29.97 fps 输入持续近 1:1 呈现，无隐藏丢帧／fallback，人工颜色、亮度、流畅性通过，生命周期与恢复通过。测试前定义统计口径与合理测量误差，不能看完结果后降低 30 fps 目标。
 
**失败或部分通过**：颜色通过但性能未达、内部渲染推进但缺呈现证据、冷态通过但热态失败等都单独报告，不合成“已完成”。
 
## 9. 每轮最小证据记录模板
 
以下为记录字段，不要求创建新的 handoff 上下文。具体原始数据放独立轮次构建目录，Lead 在既有 conversation 引用精选结果。
 
| 分组 | 必填信息 |
| --- | --- |
| 轮次身份 | run／variant、时间窗口、源码 manifest、native candidate、APK／JAR／lib hash、安装 readback |
| 实验身份 | 明确 opt-in、Session／source generation、真实 active importer、可见 output owner 关联、内部 decoder Surface 与显示身份的区分 |
| 输入 | 原始素材 hash／字节数、codec、真实 decoder、allocation／crop、原始 PTS 范围、实际输入格式／bit depth |
| 处理链 | OES 语义、transform、highp、FBO 格式、每个 pass 尺寸／格式／顺序、lease／fence／池上界 |
| 颜色 | source transfer／primaries／range、resolved target peak／reference white／OOTF、output levels、像素 range 与标签、setter 与各层 readback 的独立状态 |
| 几何 | working、each pass、EGL buffer、viewport、SF rectangle、final 布局 |
| 性能 | 冷／热条件、GPU timer 有效／disjoint、分段耗时、唯一 PTS 各阶段计数、duplicate／skip、队列／内存、A/V 漂移 |
| 呈现 | 具体方法、layer／source 关联、unique displayed、有效窗口、误差／不可测部分；无证据则填未验收 |
| 人工 | 颜色、亮度、完整性／比例、流畅性分别记录用户原意，不扩大笼统反馈 |
| 退出 | 暂停／seek／flush／取消／EOS 或 bounded stop／Back、release／retire／恢复及仍未证的资源层 |
| 结论 | 事实、推断、未验证项、下一 stage gate 是否满足、失败的明确停止点 |
 
所有选项快照、诊断 overlays、小区域 readback 与日志强度应显式记录。用于性能结论的窗口必须关闭像素 readback；过重诊断开销不能藏在“无 CPU copy”措辞里。
 
## 10. 完整验收清单
 
未勾选项都表示尚待下一会话完成，不能从本文落盘或历史测试通过自动勾选。
 
### A. 范围与来源
 
- [ ] 使用固定原始 P8.4 文件，fresh 字节／hash 核验一致，无预转码、服务器转换或低分辨率替代素材。
- [ ] 实际 decoder 保持 3840×1920、约 29.97 fps 硬解，软件解码不进入成功路线。
- [ ] mpv／FFmpeg／libplacebo／Java／Dart／工具链及 dirty 来源可追溯，构建副本已核定。
- [ ] 新 importer 有独立 native candidate／provenance／pins，旧 candidate／hash 未被冒用或覆盖。
- [ ] 新 APK embedded lib／manifest／source hash／安装 readback 一致；旧 copy 包不冒充 OES 包。
- [ ] 临时 Java17 与指定 Flutter 路径符合项目规则，未改设置、未提交／push、未清理未知 dirty。
 
### B. 输出与路由
 
- [ ] 可见 PlatformView output／visual278 精确实验门冻结，firmware／API24／arm64／hook 约束未放宽。
- [ ] 单 Session 单次 open 唯一 output owner，失败／destroy 后授权退休；无提前 fallback Texture。
- [ ] 内部 decoder Surface 没有第二显示窗口或 display owner 授权。
- [ ] 新 importer 明确 opt-in，真实 active evidence 已取得，不再报告 `mediacodec-copy`。
- [ ] 缺版本／能力／活动证据 fail-closed；候选无 software／copy／SDR fallback。
- [ ] owned options 前置管理与失败／关闭恢复通过；每变体 fresh Session，无 live interop／range 切换。
- [ ] 默认 auto、P5 DV、HDR10 direct、LYA 未加载新 importer 或改变既有默认行为。
- [ ] setter、属性 readback、最终 buffer／panel 证据各自标记，缺失未伪记通过。
 
### C. Native 与导入正确性
 
- [ ] 复用 FFmpeg MediaCodec surface／opaque buffer／PTS／release，初期未新增独立播放器或解码 loop。
- [ ] API24 Java SurfaceTexture＋JNI 真实可用，没有依赖 API26 AHardwareBuffer／API28 NDK SurfaceTexture 绕门。
- [ ] JNI class loader 显式初始化，callback 不执行 GL，GL 线程／context 正确。
- [ ] opaque buffer 所有分支 release-once，media PTS 未误用为 monotonic render 时间。
- [ ] SurfaceTexture timestamp、source identity／generation／PTS 可关联；redraw 不套错 PTS、不生成新 source ID。
- [ ] 多 retained frame 纹理内容稳定，池／queue 有界，fence／lease 安全，无每帧 glFinish。
- [ ] seek／flush／late callback／取消／退出屏障通过，不可靠时失败而非发布 stale。
- [ ] 未挪用 `mp_image.priv` 已有用途；内部 Surface 和 codec 重建协调有证据。
 
### D. 精度、颜色与几何
 
- [ ] OES 实际 RGB／range／精度行为已检验，无二次 YUV 矩阵、range expansion 或 HLG inverse。
- [ ] 未移植 Kirin P5 `1023/1020` 补偿。
- [ ] 浮点与 sampler highp、实际 FBO renderability／filterability／格式精度已验证，无 silent RGBA8。
- [ ] 灰阶、饱和色、near-black、10-bit steps 与数学参考诊断完成；readback 仅限小区域诊断模式。
- [ ] 若 standard OES 有问题，只做过一次 bounded YUV-target probe；失败时停止，没有盲集成。
- [ ] crop／transform／工作尺寸与 gpu-next 原图 crop 坐标一致，比例／边缘无错。
- [ ] decoder／OES／working／each pass／EGL／viewport／SF rectangle 分别记录；final 1440×720 未被误称 native4K。
- [ ] encoded HLG 与 linear 域、headroom／格式标记正确；非整倍数缩放的运动细节与高光质量已验。
- [ ] 已测 actual pass，不把已有 bilinear、`hdr-compute-peak=no` 或现有缩放次序当新收益，不许诺四倍加速。
- [ ] 同目标 copy／OES 的 SDR／PQ 诊断分开，copy NV12 明确为 8-bit；SDR 通过没有冒充 PQ。
- [ ] 完成一次真实同管线 full/full 与 limited/limited 对照，复用 GPU range 融合，无标签／像素错配。
- [ ] 采用 full 的前提为颜色正常且性能更好；未靠提高饱和度掩盖问题。
- [ ] resolved peak／reference white／OOTF 有依据；必要有界参考对照已记录，未拿旧无变化错误排除全部假设。
- [ ] PQ 数值与人工颜色／亮度均接受；若冻结 PQ 显示仍淡，候选明确停止，未擅改 SDR 终点。
 
### E. 持续性能与呈现
 
- [ ] 正常性能播放无解码像素 CPU 下载／再上传，诊断 readback 已关闭；GPU 内部读写和 CPU 控制开销未被否认。
- [ ] 短 gate 后完成数分钟持续冷／热窗口，条件与样本有效性明确。
- [ ] decode／latch／prepass／convert／swap wait 分离，GPU timer disjoint 已剔除并留数量。
- [ ] unique source PTS 各阶段计数、duplicates／skips、queue／memory／A/V 漂移齐全，无 hidden drop／fallback。
- [ ] 取得可关联 source frame 的有效呈现证据；SF 无效时没有重复长 polling。
- [ ] EGL／trace 或外部 120／240 fps 相机方法的身份关联、误差及缺口已记录。
- [ ] camera overlay 绑定实际源 PTS／frame identity，redraw 不增加 ID；未预转码源文件。
- [ ] 未使用 latch／swap／clock／vfps／零 decoder drops／mpv frame-count 代替 actual displayed FPS。
- [ ] 持续近 29.97 fps、输入到唯一显示帧近 1:1；人工流畅性通过。测量缺口存在时保持未验收。
 
### F. 生命周期、回归与收口
 
- [ ] pause／resume、seek、flush、失败／取消、late callback、EOS 或明确 bounded stop、Back／销毁均通过。
- [ ] 可见 owner 退休、内部 decoder Surface／SurfaceTexture、opaque buffers、JNI refs、retained textures／fences 清理有证据，无 stale。
- [ ] options 恢复与原错误／debt 语义保留，fresh Session 重入无资源累计异常。
- [ ] lab 独立 experiment 未放宽旧 copy validator；backend options／review／session／size／native gate／ledger 相关测试无回归。
- [ ] 新改动完成适当独立审核；静态／构建通过与实机／人工通过分开陈述。
- [ ] 默认 P5 DV／HDR10 direct／LYA 的所需回归证据完备；若设备或输入缺失，明确标未验证，不称全部回归通过。
- [ ] 没有将 fullscreen／旋转迁移混入本任务。
- [ ] 原始证据留 build 目录，精选证据匿名化进入 experiments；无 raw token／地址进入公开材料。
- [ ] Lead 更新既有 TASKS 与同一个 conversation Current State；本文未变成第二事实源／handoff。
- [ ] 最终报告同时给出颜色、亮度、流畅性、呈现 FPS、生命周期和测量缺口，不只报编译或零丢帧。
 
最终表述应为：
 
> 原始 3840×1920、约 29.97 fps P8.4 实时播放；工作分辨率 X，实际最终输出／显示区域 Y；实际活动管线 Z；颜色／亮度／流畅性人工验收结果分别为……；实际呈现证据方法及结果为……；生命周期结果为……；仍未验证项为……。
 
即使达标，也不能省略工作／显示分辨率而写成“native 4K 呈现”。未达标则报告真实停止阶段、失败原因与证据，不承诺后续一定能成功。
 
## 11. 新会话启动短指令
 
可直接复制以下内容作为新会话入口：
 
> 在 `/Users/wuweiwei1/src/media-kit` 执行已接受的计划 `/Users/wuweiwei1/src/media-kit/docs/plans/lg-api24-realtime-gpu-plan-20261008.md`。先读 AGENTS.md、AGENTS.local.md、TASKS 的 LG P8.4 项，以及唯一权威 topic `/Users/wuweiwei1/src/media-kit/archives/conversations/lg-h870ds-hdr-demo-20261004.md` 顶部 Current State。用户已接受“原始文件实时播放、API24 SurfaceTexture 全 GPU 导入／转换＋GPU 内缩小”主线，无需重新讨论范围；严格按阶段 0→4 的证据门执行，不以旧 SDR 验收冒充 PQ。保持现有可见 PlatformView／visual278 精确实验门、单 Session 单次 open 唯一 owner；内部 decoder Surface 不获 display owner 授权。新 importer 显式 opt-in，默认 auto／P5 DV／HDR10 direct／LYA 不变；无软件／copy／SDR fallback，每变体 fresh Session。先 query 当前设备和播放状态，不把历史 PID26640 当现状，不盲 force-stop；保护所有 dirty、旧 pins／candidate 和证据。首次工作从阶段 0 冻结真实源码／工件／pass／尺寸／resolved target 开始，再做最小 PoC；技术或测量门失败就如实停止。未获 commit／push、清理未知数据或改设置授权。只有既有 conversation 是 topic 上下文，勿另建 handoff；推进记录由 Lead 更新 TASKS／该 conversation。
 
本文落盘只完成“把已接受计划交给下一会话”的交付，不代表任何 importer、性能优化、设备验证或人工验收已经开始或完成。

