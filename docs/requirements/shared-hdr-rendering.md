# 共享 HDR 渲染核心：macOS P5 缺口收敛

状态：实施中，尚未完成颜色与产品验收。2026-10-04 用户要求跨平台使用同一套代码；本要求承接 `android-hdr-auto-output.md` R6，当前交付范围优先关闭 macOS PiliPlusX 缺口。

## 目标与归属

- mpv 的共享 gpu-next/libplacebo 核心负责帧色彩解释、逐帧 Dolby Vision 元数据、P5 reshape、目标色彩转换、渲染选项及队列重置。不得长期维护 macOS 另一套 P5 shader 或复制的色彩算法。
- media-kit 负责统一能力查询、策略偏好、输出编排及真实状态。PiliPlusX 只声明偏好并消费状态，不新增平台色彩转换或补偿。
- 平台层适配解码帧导入、Surface/FBO/Metal、显示能力及呈现与生命周期；设备采样归一化修正仍绑定确证的平台导入契约，不能将 Android external YUV 修正套到 VideoToolbox。

## 当前证据与缺口

当前 macOS mpv 0.41 的 libmpv OpenGL 路径调用 legacy gl_video；实际 arm64 二进制亦确认该链。其恢复 Dolby Vision 原颜色参数不执行 P5 reshape，后续 Metal blit不能补回转换。用户确认本地 P5 流畅但偏色；最新 Pili 4K SDR 小窗口/全屏流畅。该证据尚不足以将偏色唯一归因于 renderer，须同源参考及接入后的实屏验收。

精确当前 arm64 库的 native GPU context 未编入，不能执行同二进制 macvk 对照。隔离参考允许固定同源0.41重建必要context能力，明确不同二进制/feature身份；不得把参考库的成功当生产库成功。`cplayer=false` 不独立禁止native窗口；mpv shaderc选项与libplacebo shader编译能力分别核查。

## 实现硬约束

1. 重用共享 gpu-next 的硬件帧映射及逐帧 metadata 更新。CPU上传PoC仅证明颜色，不替代VideoToolbox硬解导入和4K60性能验收。
2. 明确输出 primaries、transfer、reference white和peak，匹配实际buffer及Layer标签；16F不等于正确HDR，色彩转换只执行一次。
3. seek、换源、HDR/SDR切换和输出重建不能使用陈旧元数据。渲染失败不得发布有效帧；P5缺少有效reshape路径时不得静默输出已知偏色的legacy结果。
4. 保留当前producer完成栅栏、buffer lease、output epoch及wakeup/shutdown释放屏障。新增backend不能将flush误当跨API读取完成。
5. 能力门禁读取实际运行库、架构与backend能力，不以marker字符串或存在libplacebo/Vulkan文件代替可用路径；后续还需真实context、导入、渲染和有效帧验证。
6. 实验opengl-next实现只作隔离研究：其硬解导入、ICC/ambient、线性EDR目标、队列与错误处理均需补齐。不得仅修改API字符串即默认启用。

## 外部 FBO 接入契约

当前 TextureHW 为半浮点 FBO 提供 `internal_format=0x881A`，SDR FBO 提供 `0`；这是现有 legacy Render API 的输入，不能直接作为新 backend 的实际附件格式证明。接入时须从拥有者的真实纹理/FBO或经过验证的显式契约取得格式、尺寸、颜色编码和位深，分别覆盖 BGRA 与 RGBA16F。libplacebo 的 OpenGL wrapper 不接管宿主纹理/FBO所有权，销毁 wrapper 后仍由宿主管理资源；同一 OpenGL API 的同步说明不能替代 GL→Metal 的完成栅栏。

当前 macOS 原生显示消费者已核对：`NativeSurfaceView` 使用 `extendedLinearITUR_2020`、RGBA16F，且不附加 PQ HDR10 metadata；`MetalSurfaceBlitter` 仅采样，不做颜色转换。因此原生 half-float 输出契约必须明确 BT.2020/linear、RGB full range 与参考白尺度，不能用输入的 PQ/HLG 标记代替输出编码。Flutter BGRA 输出需另行声明并验证实际目标编码。 当前 Dart `configureHdrOutput` 在 SDR 时请求 BT.709/BT.1886，但 macOS native layer 仍固定线性 BT.2020；接入时必须消除此不一致，以实际消费者编码确定目标，并验证 SDR/HDR 切换，不能直接将旧 payload 作为目标契约。显式外部目标不可被遗留 raw target 选项覆盖成另一编码。

macOS 插件当前为纯 Swift，Pod/SPM 仅依赖 Mpv framework。外部目标参数需有可安全构造的版本化固定布局接口；不把 libplacebo 的内部结构布局泄漏给 Swift 或要求插件复刻 API 349 的 ABI。版本、结构大小、颜色枚举和白/峰值尺度必须校验，缺失或不一致时返回明确错误。

`render_backend.update_external` 的 VO 指针只在受锁保护的调用内有效。共享核心只保留允许借用的 OSD与实际帧引用，队列需求在该调用内应用；截图、格式支持、重绘与硬解设备加载也必须接入共用核心，不能只实现 render 入口。

## 验收

- 固定P5文件及实际PTS，对照标准gpu-next与接入候选；用户确认偏色消失，另做HDR高光/中灰/色相验收。
- P5/P8.4/HDR10/SDR连续切换与seek，证明动态元数据和目标状态正确，无旧输出残留。
- 实际hwdec/帧导入、有效帧与drop观测配合用户确认4K60小窗/全屏流畅；不能用复制路径颜色通过替代性能。
- 最终同候选完成长播、暂停恢复、seek、resize/fullscreen、退出重入与无新崩溃，V2独立审核通过后方可默认启用。
- 最终universal包双架构版本、ABI、闭包、真实能力、加载与签名门禁通过；Android既有已验收路径需明确回归范围与证据，不能无证据回退。

上下文：PiliPlusX `archives/conversations/player-architecture-remediation.md`；聊天工作树 `archives/experiments/macos-ppx-completion-20261003.md` 及对应 artifacts。

## 接入后的能力门禁

现有 Pili `verify_macos_mpv_load.sh` 仅对两种架构执行库加载、初始化和版本检查（无媒体/输出）；`verify_macos_mpv_bundle.sh` 校验版本与字符串特征。它们保留为防止旧包混入的门禁，但不证明新 Render API 后端可用。

新增门禁必须在实际 CGL context 下创建 opt-in 后端，使用明确的目标契约渲染至真实 FBO，并读回非空内容；负例覆盖缺少契约、错误版本/大小、附件格式或尺寸不一致及渲染失败。另以真实 VideoToolbox 帧证明 mapper 导入、逐帧 DV metadata 和有效内容发布。arm64/x86_64 分别验证，记录实际库摘要与后端名称；普通初始化成功不能代替这些结果。屏幕颜色、亮度和运动流畅仍需用户验收。

真实 P5 CGL 探针已揭示 libplacebo 349 的 RECT 高级采样兼容问题：尺寸查询与归一化坐标生成不适配 sampler2DRect。共享硬解导入修正须对所有 RECT 使用同格式、同尺寸的 GPU 导入适配，保留逐 plane 布局与 DV metadata，缓存资源并处理 resize/失败/析构；不引入 CPU copy 或平台专属 P5 转换。

libplacebo 可在 shader 失败后禁用 scaler 并直接采样，最终 render bool 仍为 true。能力门禁必须检查累计 renderer errors/disabled hooks 与降级状态，不逐帧清除错误；同步像素读回与实际源 PTS、hwdec 报告共同证明视频内容，而非把1500次成功调用当作图像验收。

RECT→2D 缓存必须服从帧 acquire/release 所有权：同时参与队列混帧的不同源帧不能引用被下一帧覆写的同一纹理。复用只允许在最后一次使用释放后，重配置/resize/析构也不得提前回收在途缓存。验证至少覆盖两个不同图案帧同时进入 mix，确保各自内容与 PTS 绑定。
