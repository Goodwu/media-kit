# PiliPlus 源码零修改适配：实施主计划 R3

日期：2026-10-18。唯一实施分支：`compat/piliplus-zero-change-20261018`。
状态：已合入 routing 新提交，已开始 P0a 依赖审计工具实现；尚未完成应用编译、自动路由接入或设备验收。

## 0. 本轮基线和 R2 → R3 更新

用户再次提示更新后，GitHub git/ref 已读到 `routing/MK-ROUTING-20261011` 最新提交 `0a212785a87df88a0a583cd5f1f526630d5c4e81`（提交时间 2026-10-17 16:09:43 UTC，即 2026-10-18 01:09:43 Asia/Seoul）。相对 R2 的 `866c7399bf034757b2aa54e69290533dbed6bc5c`，增加 12 个提交、改变 16 个文件，不是仅更新文档。

实施分支原已有计划提交 `5e34eb74507ed658ebc57bf96f1cf6829e012925`。核对该侧仅新增计划文档、与上游无文件冲突后，以正常双亲合并提交 `e51df06e0031ce5ea3afa2ee1bd295384671c025` 纳入上游；第一父提交为原计划，第二父提交为 `0a212785...`。不重建分支、不强推、不改用户的 routing 分支。PiliPlus 本轮已读快照为 main `849c56b035ac8acf1b4fd677c2c94debe161da8e`；每轮执行前重新解析最新 refs，这些 SHA 是证据身份而非长期固定旧源码。

R2 原文保存在上述计划提交中。本文件是完整的当前执行计划，以下新决策优先于 R1/R2 旧措辞：

| 上游变化 | 本方案修订 |
| --- | --- |
| `VideoRouteOptions.sdrEmbed` 已加入 merge/fromMap/toMap/key/origins，解析 unset 为 true | 原样复用，适配器不得漏传或自行设 false；不是新建实验开关 |
| SDR embed 候选进入现有 planner/realizer | 不再开发第二条同类路径，普通入口共用该实现 |
| 显式 preferCopy 抑制 embed；源硬解 unsupported 抑制生成，unknown/无 census 不抑制 | Legacy hwdec 意图映射必须保留 copy 偏好；不能把 unknown 当 unsupported |
| SDK 16–25 能力范围内默认 embed，接受 mpv GL 超分/滤镜/字幕/OSD 不执行 | 撤销 R2 在该范围内自动检测 shader 并切 Texture 的主张；不擅自推翻上游产品取舍 |
| 受控 `setOptions(sdrEmbed:false)` 重开后才可执行新 GL 功能 | 兼容层若需要切载体，必须经同一事务并保留所有其他有效选项；否则明确拒绝，不假装成功 |
| 默认路径范围大于已验证范围，screenshot-raw 未测，复核拒绝后不保证 copy 回退 | 新增“默认构建与 opt-in 构建分开”“截图未验证”“复核失败停止”的验收项 |

依据：`media_kit_video/lib/src/routing/video_route_options.dart`、`hdr/hdr_route_planner.dart`、`hdr/hdr_strategy_realizer.dart`、`hdr/hdr_video_session.dart`、`docs/plans/android-sdr-light-presentation-20261017.md` 及新增/变更测试。上游记录不是本轮重新运行测试的证据。仅 LG/API24 的受控 opt-in 形式被上游记为端到端验证；默认构建及其他设备不因此自动通过。

## 1. 目标、边界和分层验收

PiliPlus 继续使用现有 Player.create、VideoController.create、SimpleVideo、SubtitleView、普通 open 和原生导出接口，不修改其业务/页面/播放器控制器/原生宿主/受控 pubspec.yaml，不向 PiliPlus 推代码。SDK 工具可在隔离构建副本生成根级 pubspec_overrides.yaml、lock 和平台生成文件。已发布 App 二进制不会因为库仓变化自行升级。

T0=工具正确；T1=原应用全项目编译；T2=已有功能兼容（明确列出本节后述已接受例外）；T3=普通入口真实自动路由；T4=指定路径和显示正确。五层分别验收；工具全绿、分析桩、一帧成功、verified 日志、copy/软解能播不能替代后层。

本次新增 SDR 默认 embed 的 GL 功能取舍是产品明确例外，不能继续宣称“全部功能无条件无回归”。Flutter 字幕/弹幕/控制层仍须正常；mpv GL 功能在该路径不可执行需有可见诊断。截图兼容仍是开放项，不豁免、不伪造成功。

播放器处理应用已经传入的 rendition，不能修复应用没有选择的 HEVC/AV1/DV 业务源；禁止在 SDK 中读取 PiliPlus 账户、Hive/Pref 或调用 Bilibili API 绕过。

## 2. 依赖交付和 P0a 工具

PiliPlus 根 overrides 来自 My-Responsitories/media-kit native 与 bggRGjQaUbCoE/media-kit native。必须审计整套实际包闭包，而非只替换三个顶层名称。Dart 的根级覆盖规则依据：https://dart.dev/tools/pub/dependencies#pubspec_overridesyaml 。保留非播放器 overrides；依赖包自己的 overrides 不接管根应用。

特别修正：仅出现在 dependency_overrides 中的名称未必被实际依赖。旧 `media_kit_native_event_loop` 若不在新闭包中，先记录 unresolved-override-only 并检查真实 pub 解析，不直接断言编译缺包、强制造插件或静默混装旧 fork。required 闭包中的缺包单独记 missing-required-package。P0a 对两类未决都以非零码阻止生成可用覆盖文件，后续通过解析证据解除 override-only 问题，不能删除审计记录来“通过”。

本轮落地位置：`tool/piliplus_compat/dependency_plan.py` 与测试、README、requirements，以及独立 T0 CI。输入干净 app/SDK Git checkout，读取本轮 HEAD 中的受控 pubspec；发现库包及递归依赖/平台 default_package，保留无关覆盖，在两个输入目录之外生成计划和覆盖文件；拒绝覆盖已有输出；读取失败、脏树和未决包都明确失败。验证模式检查根覆盖与计划一致、来源 HEAD 未变、package_config 中必需包齐全、播放器包不来自旧 fork、packageUri 不越界。

范围必须如实：这是 P0a 的声明审计和解析路径检查，不是完整源树快照器，不运行 pub，不编译，不冻结/审核原生库。P0b 的隔离副本、源码/模式/链接/新增输入证明、真实解析日志、资产冻结和构建器仍待实现。已有 `tool/routing_ci`/`routing_matrix` 是 Lab/PiliPlusX 链，不能直接写成原始 PiliPlus 通过。P0a 的 YAML anchors/aliases、Pub workspace 支持未实现时明确拒绝，不能用不完整解析器悄悄改写语义。

## 3. 已确认的类型和行为差异

| 项目 | PiliPlus/原 fork | 当前库 | 工作 |
| --- | --- | --- | --- |
| Player.create/别名 | NativePlayer 使用方式 | 已有别名和 create | 复用，不重复造入口 |
| width/height | int；未知 0 | int? | 公共兼容视图；内部 unknown 不变 |
| getProperty | 同步 String | 安全异步 Future<String> | 同步观察快照与严格异步事实分离 |
| screenshot | Future<ui.Image?> | Future<Uint8List?> | 明确拆分图像/字节接口，真实取帧 |
| handle | 同步 int | Future<int> | 初始化后的门面契约，核心屏障保留 |
| WebP | static NativePlayer.mpv/setHeader、Initializer.create/dispose | 实例 API/不同释放协议 | 独立安全兼容桥，非简单转发 |
| 显示 | SimpleVideo + 外部 FittedBox | Video/显式 HdrVideo | 统一渲染实现，旧布局契约 |
| 字幕 | 旧 Subtitle、拖动/padding 回调 | 基本 SubtitleView/List<String> | 全部实际参数及模型兼容 |
| 输入 | 普通 open、EDL 双流、extras 选项 | 独立 session | 自动接管及输入保真 |
| 控制器 | 原对象被长期保存 | session 可替换 controller | 对外稳定、内部切换 |
| iOS PiP | 跟踪 Texture/id/CVPixelBuffer | 非 Android session 未验证直通 | 不能盲切无帧出口原生视图 |

上述是已读源码差异，不是全项目 analyzer 结果。P0b/P1 必须列举音频页、直播页、画廊、回复截图、WebP 的实际导入/参数/返回类型/FFI，Dart analyzer 才是类型门禁，文本扫描只作清单。

## 4. 架构：兼容门面 + 唯一会话内核

```text
原始 PiliPlus
  Player / VideoController / SimpleVideo / SubtitleView / WebP FFI
                             |
                  旧 API 门面 + NativePlayerCore
                             |
               PlayerSessionDelegate（核心无 Flutter 依赖）
                             | media_kit_video 自动注册
               共享 VideoRoutingSession（抽取既有编排）
                             |
  facts -> capabilities -> 现有 planner/realizer/coordinator/review
                             |
             稳定 VideoController / 平台输出代理 -> 当前输出
```

新类名为建议命名，不代表已实现。普通与显式 HdrVideoSession 共用内核，单 Player 仅一个输出所有者，禁止双重自动注册和第二张路由表。media_kit 只定义核心操作/媒体/事实/委托；media_kit_video 承载 Flutter 布局、能力和路由，不反向依赖，不导入 PiliPlus/GetX/Hive。

公开 open 在获取底层锁前委托；内核走 rawOpen/rawStop/rawCommand，不再递归调用公开 open。play/pause/seek/stop/dispose、改变媒体的命令与 playlist 自动换项全部纳入排序、取消和代次管理。

同名成员不能同时提供 String/Future<String> 或 ui.Image/Uint8List 两套静态类型。门面组合核心，不非法 override、不用 dynamic 伪装。已有 SDK 消费者同步迁移到明确命名的核心接口并回归；Flutter 图像构造经条件实现/适配，不强加 dart:ui 给纯 Dart 使用者。

## 5. 属性、截图、字幕和原生导出

同步 getProperty 仅读取经审计属性的原生已观察/已确认快照，hwdec-current 不得从配置推断。换源、路由变化、配置确认后刷新/失效；不是任意属性的瞬时原生查询。路由门禁只用带身份的异步原生事实，绝不能消费 UI 快照；不能撤销当前避免 UI/平台线程同步 FFI 锁等待的修复。

未 await 的 setProperty/setMediaHeader 调用时即登记操作顺序；后续 open 不越过配置。异步错误进既有 stream；旧事务 rollback 不覆盖新配置版本。宽高的 0 仅用于公共兼容视图，内部仍可未知。

旧 screenshot 返回真实 ui.Image，核心 bytes/safeScreenshot 保留。嵌入直出/HDR 的实际截图通路必须实现并验色彩、尺寸、旋转和内存释放，否则明确失败；不能黑帧/空值假成功。sdrEmbed screenshot-raw 上游未验证，不能自动承诺。字幕恢复真实拖动、样式、padding 回调和模型，Flutter 层可见性独立验收。

WebP 旧代码在 Initializer.dispose(ctx) 后不 await 即 terminate_destroy，并可能位于 SHUTDOWN 回调。兼容桥必须让原生事件负载独立深复制、原生泵不等待 Dart 回调；同步 dispose 返回前停止句柄访问/关闭投递，当前回调只持有自己的副本，不能等待自身退出死锁。待投递事件按代次回收。现有异步释放不能静态转发充当同步屏障；能力不够时补原生桥并明确阻塞。核对 FFI 路径/指针类型/static API、libwebp_anim、进度、取消、并发及重复释放；不回退固定延时销毁。

## 6. 分阶段 open 与无提示源事实

PiliPlus 先 await open(play:false) 再继续应用状态更新。内核拆 accepted（请求提交并接管）、sourceReady、outputBound、verified；兼容 open 保持旧提交语义，显式高级接口可以等 verified。VideoController.create 不等待最终可见 Surface，避免 open 等挂载、挂载等业务状态循环。

准备阶段 play 只记录意图，输出可用后才放行音视频；不泄露错误色彩帧或声音。open 返回不等于 verified。失败通过旧 error stream，stop/dispose/新 open 可取消全部等待，超时/清理显式。纯音频/headless/WebP raw handle 不自动创建视频会话。

优先同一解复用链，不默认第二播放器/ffprobe。on_load 设置 headers/媒体选项；on_preloaded 位于默认选轨/decoder 之前，不能假定 current-tracks 即最终轨道。必要时在 mpv 实际选轨确定、decoder 创建前加最小事实/屏障，不在 Dart 复制选轨算法。

源事实绑定 sourceGeneration、媒体项/EDL 子流、选中轨道、codec/profile/level/bit-depth/尺寸、transfer/primaries/matrix、DV profile/compat/EL/RPU、HDR10+/Vivid 与各字段来源。容器未知字段通过有限解码阶段补齐，晚到事实只允许有边界纠正。unknown 不等于 SDR，缺失 EL 不等于 false，发现动态元数据不等于执行映射；无 hint 不能让 codec 永久空。

EDL 原文和音频子流保真，按 mpv 语法/UTF-8 字节长度处理，不 split(';')；不认识的语法保留给原生。默认头/Media 头及子请求一致，诊断不泄漏签名/鉴权。extras 仅解释实际旧媒体选项，附加数据不任意转 mpv 属性；缓存/音频滤镜按媒体作用域恢复，不能绕过路由受管字段。同 URI 再 open 也新建代次，不拿 URI 或全局 Media 缓存当事实身份。

## 7. 新 sdrEmbed 默认、旧 hwdec 和 HDR 策略

LegacyVideoIntentAdapter 映射 hwdec/enableHardwareAcceleration，软件解码要求与 GPU 渲染开关分离。显式 mediacodec-copy 等偏好须映射到 preferCopy 并压过默认 embed；不能把调用者默认值误当强制硬件要求。保存 options provenance、sdrEmbed 和其他有效字段，setOptions/openOverride 合并不丢值。

普通 open 复用新 planner 的能力准入：在其既定 SDK/import 范围内默认生成 SDR embed；源硬解明确 unsupported 才抑制，unknown/缺 census 留待现行 runtime review。不得按 LG/设备名特判，不修改 `_requiresMediacodecCopy` 或其三个 HDR/SDR 调用边界来扩权。

该默认路径接受 mpv 超分/shader/vf/字幕/OSD 不执行；不自动探测 GL 后切回 Texture，也不添加 UI 开关。兼容层在收到可识别的新功能请求时，经既有错误/诊断通道明确报告不可执行。需要恢复 GL 的高级调用通过保留其他有效选项的 sdrEmbed:false + setOptions 受控重开并确认成功后执行；不得认为直接写属性会触发切换。超出已接受默认例外的路径仍按功能需求选择合法载体或明确报冲突。

HDR 候选顺序不变：原生完整处理 -> 动态元数据重建 -> 合法基线 -> 必需传递函数转换；SDR 输出仅在现有策略允许的条件使用。HDR10+/Vivid 不提前退基线，HLG→PQ 必须真实转换而非改标签。未实现路径明确 routeNotImplemented，不另加测试开关；尝试其他合法候选不等于指定路线通过。复核失败终止语义不变，特别不能承诺 embed 失败必定回 copy。

## 8. 稳定显示、平台及事务生命周期

公开 VideoController/id/rect notifier 与平台代理身份稳定，内部后端可替换。platform.future 不能永久引用已释放首后端；首帧、initial-bound、current-bound 与输出代次分开。SimpleVideo/Video/HdrVideo 共用底层，保留 FittedBox 下固有尺寸、aspectRatio/fill/filterQuality、镜像/旋转/裁切/缩放、命中和多视图布局；Flutter 字幕/弹幕/控制保持在平台视图之上。

Android 复用既有 Texture/SurfaceProducer/PlatformView 与所有权，默认 SDR embed 的布局/挂载、截图、截图请求中取消也进入矩阵。iOS 保留应用 PiP 依赖的 Texture/id/CVPixelBuffer/帧通知；无兼容帧出口不能盲切原生视图。Windows/Linux/macOS 做接口/交付/已有功能回归，HDR 按实际后端证据分列；非 Android 未验证直通不宣称完整 HDR。没有应用宿主的平台不能仅换播放器宣称支持。

身份至少含 sourceGeneration、decoderIncarnation、outputOwner/surfaceGeneration、capabilitiesRevision、configurationRevision、transactionId；旧回调不能更新新状态。内部尝试/重建不重复向业务发 EOF/stop/position=0，真实用户动作、EOF、网络错误保留，保护心跳/历史/后台服务/PiP。

dispose 同步关闭准入、取消源/hook 准备、确认生产者停止，再释放消费者和 handle，失败沿用可重试终止后清理。后台/旋转/Surface 损失/显示能力变化同一协议。一般解码错误可能清空 facts 但不销毁 codec；facts 消失不等于重建，不拿旧缓存放行。实例身份/事实恢复补证据后决定是否物理重建，不永久设备名豁免，不以 copy/软解冒充 direct 修复。

## 9. 实施阶段、文件与关联仓库

| 阶段 | 主要范围 | 完成门槛 |
| --- | --- | --- |
| P0a（本轮） | tool/piliplus_compat/、独立 T0 workflow | 依赖审计/覆盖提案/解析路径工具及真实单测 |
| P0b | 独立 staging、源码与资源 manifest、现有构建工具复用 | 原应用精确副本、源码零补丁证明、真实 pub/analyze blocker |
| P1 | player_native、native/player、models/compat、video/subtitle | 公共类型/组件真实兼容，原应用与既有消费者编译 |
| P2 | platform_player 委托、raw 操作、media/EDL/extras | 媒体/时序/取消保真 |
| P3 | hdr_video_session/coordinator/backend、video_controller | 唯一内核、普通入口、稳定输出、分阶段 open |
| P4 | initializer/事件桥、source facts、必要 mpv/FFmpeg 协议 | 安全释放、源/实例事实和定向原生测试 |
| P5 | libs/、native build、完整 CI 和设备轮 | 最新源码产物/ABI/协议/实际路径显示证据 |

确定修改 Dart/Flutter 与交付；mpv/FFmpeg 只补经确认缺口，已有能力直接复用，不预设全面重写。不复制现有 native 打包配方，不以新 sdrEmbed 方案为由扩大到其他原生实验。

## 10. 测试矩阵与输入一致性

T0 覆盖闭包、平台默认包、root/dev/override-only 分类、无关覆盖保留、重复/歧义 YAML、脏树、拒绝写输入、来源变化、旧 fork/越界/重复/缺失 package_config。T1 覆盖所有实际导入/类型/FFI/字幕及已有 SDK 消费者。T2 覆盖点播/直播/音频/换档/倍速/字幕/Anime4K/截图/WebP/画廊，默认 embed 的已接受限制与真正兼容缺陷分列。

T3 覆盖 play:false、未 await 配置、open 后挂载、快切、seek/rebuild/dispose 交错、EDL/Unicode/headers/start/刷新、缓存/滤镜隔离、全屏/小窗/旋转/后台/Surface/多视图/PiP。T4 覆盖 SDR/HDR、unknown/冲突/晚到事实、direct/copy/软件、动态元数据候选与复核真实输出。

新增回归专门区分默认无参数 vs 显式 true vs false；preferCopy 胜出；硬解 unsupported/unknown/无 census；跨 SDK 范围；保留配置的受控切换；GL 请求显式结果；Flutter 字幕/弹幕；截图未验证；默认构建真机轮不能借 opt-in 旧轮算通过。复用并保留上游新增 `hdr_sdr_embed_candidate_test` 等测试，不削弱旧门。

测试每轮解析最新开发 refs、记录不可变 SHA/trees；生产库缓存按源码/补丁/工具链/特性精确校验，不回用陈旧 JAR。最终清单绑定 App、Dart 包、事件桥、mpv/FFmpeg/libplacebo、patch、ABI、协议、工具链及产物 hash，APK 实际 native 成员逐一核对。加载成功不等于新协议存在。源码逐文件/类型/模式/链接/新增输入证明，生成 lock/overrides/平台输出单列，不能忽略所有 diff。量化实际 decoder/surface/动作/持续呈现和显示证据，不以单帧或时间推进替代。

## 11. 交接及当前限制

每轮记录唯一分支、父/当前提交、完成文件、真实命令/退出码、CI URL/结论、未运行项、blocker 和下一项；先读本文件及交接、核对远端后续写，不再另起分支重复已完成实现。新的 routing 变化先 compare，再正常合并，不自动合并回 routing。

本轮 Codex 工作区读取返回连接错误；通过 GitHub 写入。容器实际检查未找到 Dart/Flutter，git ls-remote 失败于 github.com DNS；仅运行本地 Python/临时 Git 仓工具测试，不宣称原始 App/native 编译或设备结果。CI 的 T0 工作流独立命名，无 continue-on-error；T0 绿不能作为完整兼容总门禁。P0b–P5 仍开放。
