# PiliPlus 源码零修改适配：实施主计划 R2

日期：2026-10-18。任务：PiliPlus 原源码适配 Goodwu/media-kit routing 分支。
实施分支：`compat/piliplus-zero-change-20261018`。
状态：开始实施；不得把工具测试通过写成应用编译、播放或 HDR 验收通过。

## 0. 基线、此次复核及交接规则

2026-10-18 经 GitHub commits 和 git/ref 两种接口复核，服务端可见的 `routing/MK-ROUTING-20261011` HEAD 仍为 `866c7399bf034757b2aa54e69290533dbed6bc5c`；PiliPlus main 为 `849c56b035ac8acf1b4fd677c2c94debe161da8e`。用户说明上游有更新，但本轮尚未读到晚于该 HEAD 的提交，不虚构新增差异。新实施分支通过服务端 base_ref 从 routing 创建，随后读取新分支 ref 验证基点确为上述 SHA。基线只标识本轮，不是长期锁旧代码。

Codex 工作区首次读取返回连接错误；本轮通过 GitHub 进行读取和写入。本地容器没有 Dart/Flutter，且不能解析 github.com；不得把本地 Python 测试写成 Flutter 编译。实际执行、远端提交、CI 和设备状态分别记录于本目录的实施交接文件。

本文件取代会话附件《PiliPlus-zero-change-media-kit-plan-20261017.md》成为仓内实施主计划，保留其完整目标并补充可执行顺序。只在本实施分支延续工作；下一轮先读交接、核对远端 HEAD 和提交记录，禁止另起分支重复已提交实现。后续可见 routing 新提交时先比较提交及文件差异，再正常合并并复核冲突；不强推、不重置用户分支。所有测试取本轮最新开发源码，记录 SHA 用于复现而非长期冻结旧二进制。

## 1. 零修改边界与验收层次

不修改 PiliPlus 业务、页面、播放器控制器、原生宿主、受控 pubspec.yaml；不向 PiliPlus 推送代码。SDK 侧工具在隔离副本生成根级 pubspec_overrides.yaml、解析依赖、生成该轮 lockfile 和平台输出。构建输入允许变化，但源码零补丁必须有逐文件证据。已发布的应用二进制不可能仅因库仓改变而自动升级。

必须分别验收：T0 工具自身正确；T1 原始应用全项目编译；T2 原有功能无回归；T3 普通入口真实自动路由；T4 指定路径和 HDR 显示正确。低层通过不能代替高层。不能用分析器/测试桩通过、日志 verified=true、一帧成功或 copy/软解能播放代替 HDR/direct 持续输出验收。

应用当前根级 overrides 来自 My-Responsitories/media-kit native 和 bggRGjQaUbCoE/media-kit native。需要按实际声明和本库各包 pubspec 解析闭包，不只覆盖三个顶层包。保留所有无关 overrides；旧事件循环包也必须核对。发现本库缺少旧包时报告 missing-package，不能保留旧 fork 静默混装或造空插件。应用 pubspec.lock、SDK package_config 和各原生产物分别核对来源。

Dart 规则依据：https://dart.dev/tools/pub/dependencies#pubspec_overridesyaml 。覆盖在应用根包生成；依赖包自己的 overrides 不会接管根应用解析。本轮工具仅生成/核验输入的成功不表示 package solver、analyzer 或构建成功。

## 2. 已确认差异及必须复用的基础

| 接口/行为 | 应用及原 fork | routing 基线 | 实施处理 |
| --- | --- | --- | --- |
| Player 类型、创建 | Player.create，作为 NativePlayer 使用 | 已有 typedef Player = NativePlayer、create | 复用，不重新实现同一别名 |
| state.width/height | int，未知为 0 | int? | 公共兼容视图映射，内部 unknown 不变 |
| getProperty | 同步 String，直接字符串操作 | Future<String>，通过安全异步路径 | UI 快照门面与严格异步事实接口分离 |
| screenshot | Future<ui.Image?> | Future<Uint8List?> | 明确分离图像与字节接口；不得 dynamic 蒙混 |
| handle | 同步 int | Future<int> | 已初始化门面同步访问；核心保留初始化屏障 |
| WebP | NativePlayer.mpv/setHeader、静态 Initializer | 实例 API，释放协议不同 | 独立兼容桥与安全事件所有权 |
| 显示 | SimpleVideo + 外层 FittedBox | 标准 Video/显式 HdrVideo | 同一渲染内核，补旧布局契约 |
| 字幕 | 拖动、padding 回调、旧 Subtitle 模型 | 基本 SubtitleView、List<String> | 精确迁移实际参数/类型及功能 |
| 输入 | 普通 open、EDL 双流、extras 选项 | 独立 HdrVideoSession，extras 注释为附加数据 | 自动接入、选项作用域及双流保真 |
| 控制器 | 应用持有原对象 | session 切拓扑会替换对象 | 稳定控制器/代理，内部替换输出 |
| iOS PiP | 自有插件跟踪 Texture/CVPixelBuffer/id | 非 Android session 未验证直通 | 保留现有帧出口，不能盲切纯原生视图 |

这些是源码证据，不是全应用编译诊断。P0 生成实际 package 导入清单；Dart analyzer 才是静态类型验收，不把正则搜索当分析器。覆盖音频页、直播页、画廊、回复截图、WebP 等非主播放路径。

## 3. 唯一路由内核和包分层

```text
未修改的 PiliPlus
  Player / VideoController / SimpleVideo / SubtitleView / 原生导出
                         |
                  旧 API 兼容门面
                         |
          NativePlayerCore + PlayerSessionDelegate
                         | media_kit_video 自动注册
            共享 VideoRoutingSession（由现有 session 抽取）
                         |
        facts -> capabilities -> planner/realizer/coordinator/review
                         |
             稳定控制器与输出代理 -> 可替换平台输出
```

新增名称为设计命名，不声称已有实现。从 HdrVideoSession 抽取现有编排，显式入口和普通 VideoController 共用，禁止复制路由表。每个 Player 只有一个会话/输出所有者；显式会话不得被自动入口再次接管。该所有权机制不是实验开关。

media_kit 只承载媒体、核心操作、事实及委托；media_kit_video 承载 Flutter 布局、平台能力和路由。禁止核心反向依赖 video 或引入 PiliPlus/GetX/Hive/Pref/Bilibili 业务 API。

公开 open 在获取底层锁前委托；内核调用 rawOpen/rawStop/rawCommand，不再调用公开 open，避免递归和非重入锁死锁。play/pause/seek/stop/dispose、改变媒体的原生命令和 playlist 自动换项一起进入事务模型。

## 4. 接口兼容的安全约束

### 4.1 门面与核心静态类型

不能让相同方法同时宣称 String/Future<String> 或 ui.Image/Uint8List 两种返回类型。公开兼容门面组合持有核心，不能非法 override；内部和现有消费者使用命名明确的核心接口。Flutter 图像 API 通过 Flutter 条件实现/适配，不把 dart:ui 强加给纯 Dart 使用者。P1 必须同时验证本库已有消费者和原应用；若迁移公共模型会破坏现有消费者，则先完成两种类型面的设计和迁移测试，不批量替换类型造成新的隐性破坏。

### 4.2 同步属性与未 await 设置

保留当前避免 UI/平台线程 FFI 阻塞的修复。应用同步 getProperty 只读经审计属性集合的原生观察/确认快照；hwdec-current 必须来自实际观察，不能拿配置冒充实际。创建、换源、配置确认和切路由时刷新/失效。快照不是任意属性在调用瞬间的严格查询，兼容验收明确这个边界。路由及 HDR 门禁只用异步、带代次的原生事实。

未 await 的 setProperty/setMediaHeader 在调用时同步登记顺序，后续 open 捕获并等待必要配置。失败走既有错误流，禁止未处理 Future 或顺序漂移。配置版本变化后，旧事务回滚不得覆盖新设置。

### 4.3 状态、截图、字幕

外部未知尺寸为 0，内部保留未知。审计 state/current/playlist/copyWith、字幕模型与 stream 类型。旧 screenshot 返回真实 ui.Image；核心保留 bytes/safeScreenshot。direct/HDR 无可取帧路径时真实实现取帧和转换或明确失败，不返回黑帧成功。测试色彩、尺寸、旋转、图像释放。SubtitleView 恢复所有实际使用的样式、拖动和 padding 回调，不能删功能换编译通过。

### 4.4 原生 WebP 兼容桥

PiliPlus 调用 Initializer.dispose(ctx) 后不 await 即 terminate_destroy，且可能在 SHUTDOWN 回调内。现有异步 dispose 不能静态转发伪装为这个同步契约。

兼容桥须让事件负载独立深复制，原生泵不等待 Dart 回调；同步 dispose 关闭投递并停止对该句柄的原生访问后才返回，当前 Dart 回调继续只持有自己的副本，不能等待自身退出。待投递副本按关闭代次释放。已有安全核心的释放链不回退到固定延时；桥不能提供安全屏障时该项明确阻塞。核对旧 FFI 导入路径、指针类型、static mpv/setHeader、libwebp_anim 编码能力及进度/取消/并发导出/重复释放。

## 5. 自动 open 的分阶段协议

PiliPlus await open(play:false) 后继续更新 UI；不能把它变成必须等待最终 Surface 和 HDR 复核的 Future，否则 open 等挂载、挂载等应用状态形成循环。

内核分 accepted（请求提交并接管）、sourceReady、outputBound、verified。兼容 open 保持提交语义，显式高级 session 可等待 verified。VideoController.create 建立稳定代理，不等待最终可见 Surface。play 记录播放意图，合适输出准备完成后才放行音视频；未挂载阶段不能泄露错误色彩帧或声音。open 返回不等于 verified；异步失败必须进入应用已有 error stream。

复用 initial/current output-bound 屏障。纯音频和 headless 有独立意图；不能为 WebP raw handle 或音频 Player 自动建视频会话。快速换源/取消/dispose 可结束等待，所有阶段有限时、取消和资源退出路径。

## 6. 无 hint 的源事实、EDL 和选项

优先同一解复用链，不默认第二 Player/ffprobe（避免额外解码资源和签名 URL/直播请求）。on_load 设置请求头和媒体选项；on_preloaded 可获得容器事实，但位于默认选轨/解码器建立之前，不能假定 current-tracks 已等于最终选轨。需要时在 mpv 实际选轨确定、decoder 创建前补最小事实/屏障，不在 Dart 复制选轨算法。

事实至少绑定 sourceGeneration、媒体项/EDL 子流、selected track、codec/profile/level/bit depth/尺寸、transfer/primaries/matrix、DV profile/compat/EL/RPU、HDR10+/Vivid 和各字段来源。容器不可知字段由受限解码阶段补齐。unknown 不等于 SDR；EL 缺失不等于 false；发现元数据不等于映射/透传完成；无应用 hint 不能让 codec 永久为空。晚到事实只触发有边界的同源纠正。

原样保留 EDL 及音频子流，解析按 mpv 语法和 UTF-8 字节长度，不 split(';')；未知语法保留给原生解复用器。统一 player 默认头与 Media 头及音视频子请求；日志不记录鉴权/签名。extras 只适配实际旧选项，不能把所有用户数据当 mpv 属性；缓存和音频滤镜按媒体作用域恢复/清除，路由受管属性不可被绕过。相同 URL 再次 open 也是新源代次，URI/全局 Media 缓存不能做事实身份。

## 7. 旧配置、候选策略、失败语义

LegacyVideoIntentAdapter 联合解释 hwdec 和 enableHardwareAcceleration；软件解码要求、自动选择、显式硬解/copy 各有明确语义，不把 GPU 渲染开关等同解码开关。Anime4K/glsl-shaders/vf 进入拓扑需求；direct 无法处理时选合法路线或报冲突，不能静默丢功能。

沿用既定候选顺序：完整原生处理 -> 动态元数据重建/映射 -> 合法基线 -> 所需传递函数转换/SDR 映射。HDR10+/Vivid 不得在普通入口提前退基线；HLG 到 PQ 要真实转换，非改标签。未实现路径明确错误，不增加测试必须打开的实验开关。自动策略可继续合法候选，但指定路线的验收保持未实现/失败，不能以另一条能播代替。

播放器只能处理应用交给它的 rendition，不能修复应用未选择 HEVC/AV1/DV 的业务选源；禁止读取应用账户或另调 Bilibili API 绕过。

## 8. 稳定输出、平台和生命周期

公开 VideoController、id/rect notifier 与 platform 代理身份稳定，内部后端可替换；不能让 platform.future 永远指向已释放的第一个后端。布局、大小、nativeSurface 状态和首帧/current-bound 屏障跟随当前代次。SimpleVideo/Video/HdrVideo 共用底层实现，保留外部 FittedBox 下的固有尺寸、aspectRatio/fill/filterQuality、裁切、镜像、缩放、旋转、点击命中和多视图布局。字幕/弹幕/控制仍由应用绘制。

Android 复用 Texture/SurfaceProducer/PlatformView、插件注册和输出所有权。iOS 保留被应用 PiP 跟踪的 Texture/id/CVPixelBuffer 与帧通知；无兼容帧出口不可切纯原生视图。Windows/Linux/macOS 做 API、原生库、已有功能回归，HDR 按各自真实后端验收；非 Android 的未验证直通不得写成完整 HDR 支持。没有应用宿主的平台不能靠换播放器宣称支持。

事务绑定 sourceGeneration、decoderIncarnation、outputOwner/surfaceGeneration、capabilitiesRevision、configurationRevision、transactionId。旧回调不改新状态。内部尝试/重建不向应用重复发送业务 stop/EOF/position=0，真正用户操作/EOF/网络失败保留，避免心跳、历史、后台服务和自动 PiP 异常。

dispose 同步关闭准入，取消 hook/源准备，停止生产者并确认，再释放消费者和句柄；失败沿用可重试终止后回收。后台、旋转、Surface 销毁与显示能力变化共用协议。routing 审查已指出一般解码错误可能清空 facts 而未销毁实例；facts 消失不等于重建，也不能用缓存自动放行。原生实例身份/事实恢复需证据，是否物理重建取决于完整因果链。禁止设备名永久豁免或软解/copy 冒充 direct 修复。

## 9. 文件级工作包和关联库范围

| 包 | 位置 | 交付 |
| --- | --- | --- |
| P0 | tool/piliplus_compat/、对应 workflow | 独立原应用副本、闭包覆盖、来源/差异清单、工具测试 |
| P1 | player_native.dart、native/player/、models、compat/ | 兼容门面、静态类型与回归 |
| P1 | video/、subtitle/ | SimpleVideo、字幕真实功能 |
| P2 | platform_player.dart、native/player/ 委托 | raw/公开入口分离、事务/取消 |
| P2 | media_native.dart、媒体选项适配 | EDL、headers、extras、源身份 |
| P3 | hdr_video_session/coordinator/backend、routing/ | 共享内核、自动注册、分阶段 open |
| P3 | video_controller/ | 稳定代理及多拓扑 |
| P4 | initializer、原生事件桥 | 旧静态 API 的同步安全释放 |
| P4 | classifier/source_facts/source_spec、mpv/FFmpeg | 经确认缺口的选轨/元数据/实例事实协议 |
| P5 | libs/、原生 build 仓、CI | 最新源码产物及 ABI/协议/来源闭环 |

Dart/Flutter 与构建是确定修改；mpv/FFmpeg/平台原生只补 Dart 无法安全替代的已确认缺口，不全面重写。不复制 tool/routing_ci 和 routing_matrix 已有的 Lab/PiliPlusX 受审 native 打包配方。旧工具中与当前产品裁决不一致的 gate/旧基线说明不是新方案规范；新工具不能直接套它们宣称原应用验收。

## 10. 执行顺序、输入一致性和测试

P0 先提交可运行工具和单元测试，再运行真实依赖解析/分析取得 blocker；P1 消除类型和组件缺口；P2 保真媒体和操作时序；P3 自动路由；P4 安全原生协议；P5 全平台/设备闭环。各阶段状态单独记录，不使用 continue-on-error 或空桩掩盖兼容失败。

本轮 P0 收敛为生成/验证工具：输入干净的本库和原应用 Git checkout，复制精确 HEAD 到全新输出目录，不写源工作区；从本库 tracked pubspec 发现包，递归收集播放器依赖，保留非播放器 overrides，缺包明确阻塞；验证 package_config 的播放器路径均指向本轮副本；保护受控源码、符号链接、模式及新增源码，只有明确列出的根生成输出例外允许变化；生成 package/import/源码 hash 清单。报告中 applicationCompile/device/HDR 默认 not-run。该工具不冒充原生产构建器，不默认消费旧 JAR，也不自动安装 App。

后续完整构建每轮解析最新开发 refs，记录不可变 SHA/trees；源码及补丁/工具链相同才可命中原生产物缓存。清单记录 App、Dart 包、所有 media_kit_libs_*、事件桥、mpv/FFmpeg/libplacebo、patch、ABI、工具链、特性协议和产物 hash。package 能加载不等于新协议存在；旧原生库或必需接口缺失明确失败。APK 内 native 实际成员与本轮来源逐一绑定。原应用源码逐文件不变；lock/overrides/生成项单列，不能通过忽略全部 diff 蒙混。

| 验收层 | 用例 |
| --- | --- |
| 工具 | 覆盖合并、闭包、缺包、脏树拒绝、隔离副本、源码/模式/链接篡改、外部解析路径拒绝、失败 receipt |
| 静态 | 全部实际导入/构造/返回类型/FFI/字幕；原 App 和已有 SDK 消费者 |
| 功能 | 点播/直播/音频/换档/字幕/倍速/Anime4K/截图/WebP/画廊 |
| 输入 | EDL 双流、Unicode、请求头、start、刷新续播、缓存和滤镜隔离 |
| 时序 | play:false、未 await 设置、open 后挂载、快切、seek/rebuild/dispose 交错 |
| 显示 | 全屏/小窗/旋转/后台/Surface 重建/多视图/Android 与 iOS PiP |
| 路由 | SDR/HDR、未知/冲突/晚到事实、direct/copy/软解、动态元数据所有候选 |
| 原生 | 回调内 terminate、播放导出并发、重复释放、facts 清空与恢复 |
| 设备 | 实际源/轨道/decoder/surface/处理动作/持续帧与显示证据，不以单帧替代 |

## 11. 每轮交接必须落盘

记录任务 ID、唯一实施分支、父提交/当前提交、完成路径、运行命令和真实退出码、CI URL/结论、未运行项、blocker、下一项。同一轮先提交主计划再实现。下一轮先验证已有提交，不重新创建同名实现。新 upstream 更新未读到时如实记录，不声称已纳入。不得自动合并回 routing；需在所有要求达到后再审查合并。
