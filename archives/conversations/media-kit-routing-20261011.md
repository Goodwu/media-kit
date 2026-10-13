# MK-ROUTING-20261011

## Current State

CORE 按用户最新“先合 DEVICE、CI 等其它工作暂停”的指令完成本次源码归并。唯一公共集成分支仍为 `routing/MK-ROUTING-20261011`，公共主 PR 不向正式 base 合并、不发布。原 DEVICE 继续 native 原 PR 的配方修复与实机工作，没有新增 DEVICE 工作线。归并认领与显式处置见 [6128883314](https://github.com/Goodwu/media-kit/pull/4#issuecomment-6128883314)、[6128920010](https://github.com/Goodwu/media-kit/pull/4#issuecomment-6128920010)。

### 本次归并与来源

| 范围 | 来源与处置 |
| --- | --- |
| App PR3 | `9895e7dc040cdc06a33cceba4d4379eba3f596b5` 的9个代码/测试文件原字节归入：DV003 嗅探/缓存/选源、DV005 Session hint/reopen 透传、DV006 Android亮度通道，以及 debug去除`.debug` suffix。状态为 `CODE_INTEGRATED_KNOWN_ISSUES_OPEN`。 |
| 库 PR6 / DV004 | `9a2c5768dd10e71975b7c3e76bb7125460a43e5b` 原始两文件完整归档；保留公共 gather 和既有跨轮拒绝断言，仅归入两项兼容 final-plan 负例。FIRST-complete-only 生产行为与成功夹具未启用，两个用户决定仍开放。 |
| 库 PR5 | `dc41787082752f234fed85db7fb7be3bd855cc45` 归入 Git 来源历史，两脚本精确归档为非执行`.sh.txt`；已有公共matrix/审查文档及三provenance banner保留。两脚本继续排除于可执行配方。 |
| native DV001 | 已建立同名公共 routing ref，指向 `1095a43acb4d0973b8bca59c5da4e300657bdb29`，完整纳入3笔原 DEVICE 提交。原 DEVICE/feature/main 未改、原PR1仍开放。仅源码纳入，没有运行或批准配方。 |

本次归并的公共父提交为库 `ebb00b8a0dedec42a68b84a4ec6e7dffb6c17f02` 与 App `ed0dc2bfc7f51ac3dc14a7f676451db27ecea6a7`；来源、完整文件blob/SHA与每项保留/归档/延后处置在 `Goodwu/media-kit:docs/plans/core-device-integration-20261012.json`。最终发布的准确新HEAD由本提交及中央回读回执绑定。FFmpeg仍为`9aba43cfbee182ade060cdccbe15340a0fbe3e83`。

### 合入后仍开放

- DV003：producer的revision/cid/baseUrl键与selection的spec.key消费断接，in-flight不共享等待；成功HTTP body仍可能无期限等下一chunk、错误take按chunk而非byte；本地videoUrl空值、完整签名URL日志、轨道/sample-entry与BL/RPU/颜色冲突门仍需修复。reopen的initialDoviFacts透传已修并保留。
- DV006：NaN reset、事件线程、应用亮度事件不发送、系统权限/写入结果、cached engine残留Activity handler继续按review5493423824开放。新读[DEVICE回报6128050177](https://github.com/Goodwu/PiliPlusX/pull/3#issuecomment-6128050177)称用户已在LYA手动确认手势数字/实际亮度联动、自动切手动；这项观察不覆盖上述问题。
- DV004：实际decoder identity序列、临时诊断范围与“最终plan履行/捕获真实切换”的语义未决定。保留公共断言，不能把Git ancestry合入写成行为修复。后续DEVICE增量必须对照 disposition 核完整生产文件，不能仅看增量diff。
- **DV001/PR5的配方整改、fresh native、JAR/APK来源、设备HDR与持续性能验收仍为必需、未完成范围。** 读取失败拒绝、双Vulkan独立组合、失败传播、clean staging、精确成员、实际链接/patch/NDK/helper与产物哈希仍待原DEVICE补齐；接受ledger空，批准native输入0。

### 暂停范围与既有证据

本次提交使用`[skip ci]`，CI跟进/新构建/其它代码切片按用户指令暂停；没有查询本阶段的新CI结果，也没有把旧结果借给新合成向量。本机仅做Git三方结构、逐文件来源、保留项与提交回读检查；没有新Flutter/Dart/Kotlin/native执行结果。现有workflow和批准门不变，原有runs不改动。

此前完整受验组合仍严格为App`3884d3e8`+库`4d1d4b7d`，其宿主证据已由ebb/ed0归档，索引`docs/plans/core-lifecycle-bootstrap-host-ci-checkpoint-20261012.json`。旧general38275707106仅保留16:49:33 UTC的最后观察；本阶段不续查或预设其终态。历史a3b577+e269d报告SHA256`156cd314f670a3d958cea70beb3818a4ea3b6dba0d3e9d944e20b8d1858705da`保持原字节。

当前CORE Web快照/等值URI修复、Session订阅修复、精确Flutter pin引导及源码来源门继续保留；已完成query/DASH/F01/R01/config/FFmpeg不重开发。experimental默认false、true主验并回归false；LG YUV8/FULL/range1、精确设备门和owner/ACK/lease保持。普通Session、owner/carrier、完整生命周期、HDR与持续性能继续分层验，10-bit与lease融合继续延期。

### 后续边界

用户已追加授权“确定已合并的情况下，删除相应分支”。逐一回读归并父提交、源文件处置和未前进的来源HEAD后，清理已确认归并的App PR3、库PR5/PR6来源分支；实际删除与ref回读登记中央PR4。全部公共routing保留；native原PR1仍未合到feature base，保留其DEVICE分支供原配方修订。已删除来源分支的App/DV004后继修改由同一DEVICE从公共HEAD出发，先中央认领，原review问题持续跟踪。CI与其它开发维持暂停；DV004两个决策点不在本轮代为裁决。

### 2026-10-13 路由设计复核、目标态裁决与本分支两笔代码修复（本合并带入）

2026-10-13 Lead 派发 Specialist 完成"含 experimental 面的完整路由合理性"只读复核（未改码）。72 格 = 37 experimental / 21 unsupported / 13 verified / 1 inherited；experimental 按入口分：默认偏好表 12 + 列表外安全网 2（dvP82、hdr10Plus × toneMapSdr）+ 仅自定义偏好 13 + realizer 恒拒 10；dvP81/dvP7 × metadataReshape 初次规划被 baseLayerDirect 支配，经会话失败重试截断列表仍可达（三种可达口径需区分）。关键问题：安全网 gateMaturity=false 一并豁免 unsupported（dvP10 × toneMapSdr 被选中，且 planner_test 已编码该行为，属文档/测试与需求状态表的契约矛盾）；DV 源 toneMapSdr 保留 RPU 却报 appliesDynamicMetadata=false（dvP82 与 sdrDirect 的显式 strip 不一致，原生是否消费 RPU 未验证）；realizer 读取 mkst bridge FFI 动态状态，同 source/caps/options 非纯确定函数；P7 "仅 MEL" 准入实为 enhancementLayer==false，现数据模型分不出 MEL/FEL。优化方案：第一批 A（安全网契约拆分，保守/兼容两案待用户裁决）+ F（isSafetyNet/成熟度豁免可观测性与证据分层）；第二批 B（SDR 源元数据处理显式契约，dvP82 优先）+ C（bridge readiness 快照化）；第三批 D（experimental 按格 allowlist，保留全局开关）+ E（10 恒拒格改 unsupported、默认列表 3 个恒拒占位标记、表测试加唯一键/完整性/可达性见证）。不建议仅凭 verified 将 hdr10 × metadataReshape 纳入默认列表（verified=准入≠默认偏好，且 appliesDynamicMetadata=false 非真重建）。实施待用户方向。

2026-10-13 用户裁决路由目标态：experimental 只是开发阶段不作路由类别，未实现/未验证进积压清单；四原则（HDR显示+HDR解码禁 tone-map／可解码且显示匹配用直通／不匹配走 reshape/convert／SDR 显示播 HDR 用 tone-map）。Specialist 两轮交付设计骨架（3 主判断、nativeDV 归直通、HDR 显示全链失败阻断不落 SDR 兜底、off/require 冲突报 routeOptionsUnsatisfied、P8.2/P10-compat2 SDR 层直用、缺报≠SDR）后两次流断开，按失败封顶规则 Lead 回接收编成完整目标态方案（决策树＋12 源类映射表＋能力三值口径＋积压矩阵取代成熟度门＋迁移三批）已呈报；待用户裁决 4 点：off/require SDR 冲突取向、HDR 全链失败阻断确认、显示能力缺报阻断确认、allowExperimental 废弃节奏。

同日设计迭代四轮用户裁决：① dvP5+非DV HDR 显示走 reshape（P5 管线→PQ，verified 路由，Lead 初版表误标阻断）；② HDR10/HLG 删假 reshape 档；③ PQ 基线源（hdr10/dvP81/dvP7/hdr10Plus）删 ④convert——所有 HDR 面板支持 PQ、不做 PQ→HLG；④ dvP82 删 ④SDR→PQ 上变换（非标准操作、丢弃 RPU 伪 HDR，无 P5 管线→阻断，已确认）；⑤ 立不变量"HDR 可得不交 SDR：SDR 输出仅在源本身 SDR 或显示明确 SDR"；⑥ 阶梯定序 动态元数据优先：①DV原生直通 → ②reshape（仅 DV，P5 管线→PQ，P7 限无EL）→ ③基线直通（PQ 恒可行/HLG 需声明）→ ④convert（仅 HLG→PQ）→ 阻断。hdrVivid/hdr10Plus reshape 为待实现积压，播放不依赖（基线直通/convert 已覆盖）。映射表 v5 与决策树已交付，等待 4 点裁决后开工批 1（planner 决策树重写）。

2026-10-13 平台线程 ANR 修复提交（media_kit）：引擎合并线程拓扑下 Dart 根 isolate 运行于平台线程，同步 libmpv 调用取 `mp_dispatch_lock`，该锁在启动/复核/输出重建期间可被 VO 等待平台线程 surface 工作时持有——平台线程等 mpv、mpv 等平台线程，死锁成 ANR。改动：① `Initializer` 主 isolate 事件泵去 `kDebugMode` 限定（release/测试同走 isolate pump，`mpv_wait_event()` 固定在泵线程），`dispose` 与 `create` 镜像同路；② 新增 `media_kit/lib/src/player/native/core/mpv_api_isolate.dart` 专用 API isolate（与事件泵刻意分离——属性读阻塞在 core lock 上不得妨碍泵 drain 事件队列，否则事件队列饱和反压 core 整体死锁），`getProperty`/属性观察读值/hook 内 `http-header-fields` 写入与置空/`playlist-pos` 读/`hook_continue`/`setPropertyString` 全部改经该 isolate 执行（仅 `configuration.async`；`allowDisposed` 直接路径保留保释放顺序），同步手写 FFI 分配释放随之下线；③ `mpv_set_property_async` 回复超时 5s→30s（首帧 VO 初始化 GPU context+shader 编译在慢 GPU/模拟器合法超时，await 异步不占平台线程）。验证：改动文件 `dart analyze` 零 finding；真机验证未跑，待平台线程拓扑设备复验。

2026-10-13 解码履行复核门竞态修复提交（media_kit_video `hdr_decoder_review.dart`）：五机回归 marble hdr10 首跑的 `HdrDecoderReviewFailure("Observed decoder changed")` 间歇 flake（同路由复跑通过）根因是双采样落进 decoder 正在打开/视频参数尚未稳定的窗口。改动：双采样一侧为空视为 decoder opening、`video-params/*` 差异视为 settling，均重试取稳定样本；decoder 身份 endpoint 双侧均已稳定仍不同才判失败（该异常正是此检查存在目的，不放松）。DEVICE 侧 DV004 同文件修复 `0fb163c6` 已在终审整改 `9a2c5768` 回退，远端净零，本修复为该竞态现行修法。验证：`dart analyze` 零 finding；marble hdr10 复跑待验。

## History

### 2026-10-12：用户要求优先归并DEVICE之前的Current State（历史快照）

唯一公共集成分支 `routing/MK-ROUTING-20261011`；CORE 唯一公共集成，原 DEVICE 继续 native 构建、实机及原 PR 修订。主 PR 保持 OPEN/DRAFT、未合并、未关闭、未发布。两个隔离 checkout 的实现提交已推送回读；未知原 checkout 修改与 App `.zcodeignore` 未触碰。

### 已完成的实现与当前宿主验证

- Web `setShuffle` 快照写时复制与所有 URI 等值时的同步死循环修复已实现，保留确切条目/index；定向测试现为6项。新general38275707106@4d1d已实际运行；Web定向步骤16:46:55–16:47:22的metadata为success，完整Chrome从16:47:22继续执行。预期6项的实际case日志尚未取得，不能称已读6通过或full完成。
- Android能力通知按存活 listener 集合保留订阅，一个 Session 退出不关闭其他 Session 的通知。新增5项真实 Session/MethodChannel 用例已实际通过，全套777通过、3跳过；native显示器事件、多engine/视图和完整owner/ACK/lease仍另验。最后disable失败的自动重试未实现。
- App使用已有Python读取唯一精确Flutter pin，在SDK安装前直接传版本并在安装后复核；Linux consumer来源包含新helper。Windows实际job已跳过yq、使用3.47.2并完成fresh bootstrap，旧HTTP504引导阻断消除。
- 本机相关Python109通过及独立源码审查保留。旧本机全量509 ran/1fail/5errors/5skip和短/tmp夹具失败均属已归档历史，不能改写；本次完整hosted Python515通过、2跳过另有实际证据。

### 精确组合与实际产物

本轮完整受验组合为 App `3884d3e8f4f38ebd6043c9be5c8dc6cef46e4377`（tree `babf93595feed078058608d6aada5c4dd014ddd5`）+ media-kit `4d1d4b7d23d66e8c7de82c3955238c4a0dd159c2`（tree `34dfc9a45c039e2f1da327f057dc8807f1cf3df3`）。本次台账归档提交不继承该组合的测试标签。

| run / attempt1 | 已核事实 |
| --- | --- |
| App source38275714484 | SUCCESS；5实际ZIP全核，四平台Flutter各268/analyze0，Python515通过+2跳过=517，Chrome DOM1/Web compile及各Dart/资源bundle成功。 |
| App Build38275715109 | FAILURE；7success/6failure/2skip，11实际ZIP全核；其自身5个source子job全部通过，没有借用standalone证据。Android/Pink为空accepted manifest，commands=[]；Linux/Windows/macOS/iOS为SOURCE_PREPARED_NATIVE_BLOCKED。 |
| library source38275707566 | SUCCESS；3实际ZIP全核，video777通过+3跳过（新增5项确实执行）、lab298、analyze0、工具45。 |

16份App ZIP的57步fresh收据、2733源码hash（App lib/test1443+media-kit tracked1290）、261package roots/10本地库包及SDK源码/补丁身份均已独立核验。其中10份source ZIP另核source.txt，6份native诊断由bootstrap与vector收据绑定。App SDK为Flutter3.47.2/Dart3.13.2，库source为3.47.7/3.13.5，分开记录。App诊断ZIP只含kernel/完整Web输出哈希与步骤证据，没有独立归档这些二进制字节。

iOS本轮1920文件、两份批准patch已独立重放；5814条数组commands全部exit0，其中5760=1920×3逐blob读取，其余54条。没有启动native Xcode构建。Windows job114900616789/artifact11758389846已完成fresh准备并抵达native gate；这证明引导修复，不是native批准。

上一轮a73 general38272288190已SUCCESS（23success/1release skip）：Web实际定向4通过、full63通过/27跳过；Linux/Windows各81通过/18跳过，macOS88通过/17跳过。mac有2次Retry、2条OutstandingWork及1条失败标记，按重试后成功保留。8实际ZIP/450内层文件、6上传job日志全核；payload中无source.txt，Android仍为旧发布JAR，不能替代fresh DV001。

query38275707339实际34断言与Android plugin Java编译通过；Darwin38275707332实际9项。OHOS38275707109用独立PR merge3222682893e9659fe44fbaa8977b160aa9bfe99a及另一SDK，HAP未独立下载，不合并为此组合的设备/HDR验收。旧1fcc+a73、a98+0c、13b+5834、a3b+e269报告保留原向量；历史156cd314…报告两仓原字节不变。

### DEVICE 最新复审与必需剩余

AppPR3 `9895e7dc040cdc06a33cceba4d4379eba3f596b5` 的DV006已在[原PR review5493423824](https://github.com/Goodwu/PiliPlusX/pull/3#pullrequestreview-5493423824)回交并逐字回读：正文REQUEST_CHANGES，GitHub状态COMMENTED。新增P1为NaN reset使后续亮度getter范围校验失败；四项P2为线程派发、应用亮度事件未发送、系统权限/写入结果未核及cached engine遗留Activity handlers。原五份DOVI/selection/controller文件与b180相同，key/HTTP body预算/in-flight竞态、本地URL/签名日志、轨道与颜色冲突仍在；9895自身Build38274961135失败，不借旧日志解释它的新run。原DEVICE在原PR继续修，当前公共实现未归入这份回交。

**DV001/PR5完整native、产物和设备归并必需未完，批准native输入仍0。** DV001仍1095a43a，PR5仍dc417870；符号读取失败拒绝、双Vulkan独立覆盖、失败传播/clean staging/精确成员、实际链接/patch/NDK/helper与最终JAR/APK可复核性由原DEVICE补齐，CORE复审。两recipe继续排除，三历史provenance banner保留。

PR6@9a2仍REQUEST_CHANGES；实际decoder identity序列、跨轮guard以及用户对临时诊断范围、最终plan/真实切换验收的两项决定继续开放。普通Session/owner/carrier/完整生命周期、HDR与持续性能继续分层验，不能以宿主测试或旧发布JAR代替。experimental默认false、true主验并测false；LG YUV8/FULL/range1、精确设备门、owner/ACK/lease保持，10-bit/lease融合延期。

### 下一步与证据入口

核当前general38275707106的Web6与完整套件实际日志/产物；保留已执行的4d1d输入。原DEVICE在原PR补DV001/PR5与PR3/PR6修订，CORE续审。下一生产切片须先核认领。

完整证据索引为 `Goodwu/media-kit:docs/plans/core-lifecycle-bootstrap-host-ci-checkpoint-20261012.json`；冻结报告按原字节及SHA归档。中央[实现推送6128112984](https://github.com/Goodwu/media-kit/pull/4#issuecomment-6128112984)、[DV006复审6128220148](https://github.com/Goodwu/media-kit/pull/4#issuecomment-6128220148)及[本轮源码终态6128436938](https://github.com/Goodwu/media-kit/pull/4#issuecomment-6128436938)保留；新的准确HEAD与执行观察继续发布中央PR4。不得把已完成query/DASH/F01/R01/config/FFmpeg/SDK接线按旧planned字段重做。


### 2026-10-12：宿主CI终态归档前的Current State（历史快照）

唯一公共集成分支 `routing/MK-ROUTING-20261011`；CORE 唯一公共集成，现有 DEVICE 保留 native/实机和原 PR 的单写范围。所有主 PR OPEN/DRAFT，未合并、未关闭、未发布。未知原 checkout 修改和 App `.zcodeignore` 未触碰。

### 本阶段已实现，当前提交尚待 hosted 验证

- `CORE-WEB-SHUFFLE-02`：所有 URI 等值时跳过不可能结束的同步 shuffle 循环，保持确切条目/index；恢复时相同 identity 序列保持当前重复条目。新增2项确定性测试，结合前阶段4项后定向共6项。普通混合 URI 的随机方式保留；混合重复 URI 与增删队列映射仍另立未完项。
- `CORE-CAPABILITY-SUBSCRIPTION-01`：Android shared channel 的 enable 按 caller=true 或仍有 listener 计算；一个 Session 销毁不能关闭其他 Session 的显示能力通知。新增5项真实 forTesting Session/MethodChannel 测试，包括存活 Session 实际 re-query、重复注册、迟到 false、延迟 ACK、失败与显式重试。未加计数器/状态缓存，未改 Session/gather、Java、owner/ACK/lease。最后 disable 失败的自动重试不在本切片。
- `CORE-BOOTSTRAP-VERSION-01`：已安装 Python 读取 App pubspec 的唯一精确 Flutter pin，直接传 flutter-version，避免安装 yq；SDK 安装后复用同一解析器严格核 frameworkVersion。拒绝歧义/引号重复键/多行值，保留当前 pubspec 与 platform lists。新 helper 加入 Linux 固定 consumer 来源集合，旧 native 门不变。

认领 [6127642516](https://github.com/Goodwu/media-kit/pull/4#issuecomment-6127642516)、[6127809360](https://github.com/Goodwu/media-kit/pull/4#issuecomment-6127809360)、[6127846798](https://github.com/Goodwu/media-kit/pull/4#issuecomment-6127846798) 已发布回读。三项独立源码审查均通过；本机最终相关 Python **109项通过**（11+31+57+10），diff检查通过。完整本机尝试失败：509 ran / 1 fail / 5 errors / 5 skipped，原因是 macOS 专用操作及缺少真实 Flutter SDK；不能写成本机全量通过。早前短/tmp造成既有260字符夹具失败也保留，最终相关测试在记录的较长临时根通过。本机无 Dart/Flutter/Chrome/Pwsh/ADB，新 Dart 测试尚未运行。

### 已完成的准确 CI 组合

本阶段写入前公共 HEAD 为 App `1fcc367cd98e77a217f8a70a388fcfcdaf92aad4` + media-kit `a73d570b633a949aab6a31e8f68ec03a13643c31`；下表只证明该组合，不能重标给包含本阶段修复的随后提交。

| run / attempt1 | 实际终态与可证明范围 |
| --- | --- |
| App source38272335487 | SUCCESS；5实际ZIP全核，四平台各Flutter268/analyze0，Python504pass+2skip=506，bundle/Chrome DOM1/Web成功。57fresh receipts、2720源码hash、261roots/10库包全核。 |
| App Build38272335840 | FAILURE；7success/6failure/2skip，10实际ZIP全核。Android/Pink空selected manifest、commands=[]；Linux/macOS/iOS为SOURCE_PREPARED_NATIVE_BLOCKED。Windows在yq下载HTTP504后退出，未开始private SDK/source bootstrap，无fresh receipt或artifact。批准native候选0。 |
| library source38272288163 | SUCCESS；3实际ZIP全核，video772pass+3skip、lab298、analyze0、Python tools45。App SDK3.47.2/Dart3.13.2；本库独立source SDK3.47.7/Dart3.13.5，分开记录。 |

旧 general38266780432（head0c6ffeaf，实际merge65531539）现已SUCCESS，23success/1skip；Web61+27skip、Linux/Windows各81+16skip、mac88+15skip。mac日志的字幕失败、两次retry和OutstandingWork保留。8真实ZIP/450内层文件已核，但Android使用v2026.013旧JAR，不能替代fresh DV001。新 general38272288190@a73d的Web定向step metadata已成功，完整suite仍运行；尚未获得终态日志，不能把预期4条写成实际已读4pass，也不覆盖本阶段新增6/5测试。

iOS1918base文件/两批准patch重放和5808receipt commands（5754逐blob读取+54其它）均只属源码证据，未Xcode构建。旧a98+0c、13b+5834、a3b+e269各报告继续保留原向量，历史SHA156cd314f670a3d958cea70beb3818a4ea3b6dba0d3e9d944e20b8d1858705da两仓原字节不变。

### DEVICE 回交与必需剩余范围

DV001仍1095a43acb4d0973b8bca59c5da4e300657bdb29，PR5仍dc41787082752f234fed85db7fb7be3bd855cc45，PR6仍9a2c5768dd10e71975b7c3e76bb7125460a43e5b。**DV001/PR5完整native、产物、设备归并必需未完**：读取失败闭合、双Vulkan独立全组合、失败传播/干净staging/精确成员、真实链接/patch/NDK/helper/JAR/APK均待原DEVICE修与CORE复审。公共matrix及历史审查已部分归入，三个provenance banner保留，两shell recipe继续排除，native接受ledger仍空。

AppPR3 b180旧受审代码仍有producer/consumer key断接、HTTP body期限/in-flight竞态、本地URL空值/签名日志、轨道/颜色冲突，review5492931759正文REQUEST_CHANGES/API COMMENTED。其Build38270385174已FAILURE：各平台实际source/patch/lock/输入门失败，source子job在routing SHA门停止；唯一380B诊断ZIP不是产物。16:05后新AppPR3头9895e7dc040cdc06a33cceba4d4379eba3f596b5只加DV006 Kotlin亮度通道，与上述修复无关；中央6127973022已读，正在原PR增量复审，不继承旧报告的受审SHA或视为批准。

PR6@9a2 review5492587336仍REQUEST_CHANGES；跨轮guard和用户两项DV004诊断/验收语义决定仍未解决，CORE不放宽。普通Session、实际owner/carrier、完整生命周期、HDR与持续性能继续分层验收；experimental默认false、true主验并回归false，LG YUV8/FULL/range1、精确设备门、owner/ACK/lease保持，10-bit/lease融合延期。

### 下一步与证据入口

本阶段commit/push/readback后核准确新向量的Web6项定向/完整suite、video新增5项/完整suite、App引导与完整source结果；保留进行中的a73旧run，不为插队取消或重标。继续原DEVICE新回交复审，不并写native/sniffer/gather。代码和各CI的冻结报告均在 `Goodwu/media-kit:docs/plans/core-lifecycle-bootstrap-checkpoint-20261012.json` 索引；后续真实HEAD与run capture发布中央PR4，旧结果只证明旧组合。

### 2026-10-12：生命周期/引导检查点之前的Current State（历史快照）

唯一公共集成分支 `routing/MK-ROUTING-20261011`；CORE 唯一公共集成，原 DEVICE 继续 native 构建、实机和原 PR 修订。主 PR 保持 OPEN/DRAFT、未合并、未关闭、未发布。原 checkout 未知 dirty/untracked（含 App `.zcodeignore`）未触碰；两个隔离 routing 工作树在开始本切片前均 clean、ahead0/behind0。

### 当前 Web 实现检查点

`CORE-WEB-SHUFFLE-01` 已完成生产改动和独立源码审查，**新代码的 hosted 执行仍待验收**。原认领6126963656，新增 Web CI 写范围 [6127346332](https://github.com/Goodwu/media-kit/pull/4#issuecomment-6127346332) 已发布回读。`real.dart::setShuffle` 在启用和恢复时使用新列表，避免改写已经公开的 state/stream Playlist；不改 equality、distinct、native 或共享 Session。新增两个 Web-only 确定性回归分别检出启用和恢复分支的旧快照改写，验证当前唯一条目/index、成员、两轮 true/false 和重复调用事件数量。恢复分支回归仅验旧快照不可变，不为 shuffle 中增删队列的既有成员策略背书。

原两项 shuffle 测试保留，纠正“增加随机样本即可消除故障”的误导注释。`ci.yml` 只在 Web job 的原完整 Chrome suite 前增加4项 shuffle 定向执行。独立静审确认可提交；修正了 dispose 不发送空 Playlist 的测试误设。`git diff --check` 通过。本地没有 Dart/Flutter/Chrome，未执行新红/绿用例；旧失败38255531407仍只证明原向量，不写成已对候选执行红测。完整静审和源码/blob/hash 见本检查点索引。

另发现两个真实相邻问题，未夹带修复或称完成：所有 URI 等值时现有 while 不会结束；indexOf 按URI比较会丢重复条目身份。需要后续独立认领与确定性验证，不采用扩大随机列表、重试、延时或简单 identical 替代完整条目语义。

### 本检查点之前的最新准确源码验收

本次写入前远端为 App `a98a57f2892592d5b8a25d6533ede4580d412ae5` + media-kit `0c6ffeaf2f509c38f8c76eca42ee255bd69b8cd2`；以下运行只证明该组合，随后 Web/文档提交必须另验。FFmpeg `9aba43cfbee182ade060cdccbe15340a0fbe3e83`；DV001 `1095a43acb4d0973b8bca59c5da4e300657bdb29`；PR5 `dc41787082752f234fed85db7fb7be3bd855cc45`；PR6 `9a2c5768dd10e71975b7c3e76bb7125460a43e5b`；App PR3 `b18086d0d654a5f523296b41bdfb869c588cd3f0`。

| 运行 / attempt1 | 精确输入 | 本轮实际结论 |
| --- | --- | --- |
| App source38266831541 | a98a57f + 0c6ffeaf | SUCCESS；5真实ZIP全部摘要/size匹配；四平台Flutter各268、analyze0，Python504pass+2skip=506，bundle、Chrome DOM1/Web成功。 |
| App Build38266831911 | 同组合，独立jobs/artifacts | FAILURE；7success/6failure/2skip；11真实ZIP全核。Android/Pink native selected manifest空、commands=[]；其他四平台SOURCE_PREPARED_NATIVE_BLOCKED。 |
| library source38266780378 | 0c6ffeaf | SUCCESS；3真实ZIP全核；video772pass/3skip、lab298、两analyze0、Python工具6+12+27通过。 |
| library general38266780432 | run head0c6ffeaf，实际merge65531539 | 取证时仍in_progress；四平台package tests终态与全部artifact内层审计待续，不能称绿。 |

App source/Build的57步fresh receipts、before/after/final向量、261 package roots中的10个库包均匹配。新源码清单为 **2714项**（App lib/test1442 + 库tracked1272）；固定Git树独立重算全部匹配，39个Swift symlink按同树目标解析。iOS1918个base文件和恰好两个批准patch变换已独立重放一致，bundle后停native门，未运行Xcode。App SDK是Flutter3.47.2/Dart3.13.2；库独立source实际使用3.47.7/3.13.5，不混标工具链。kernel/完整Web编译产物字节未归档，只承认日志与digest收据，不声称独立重算这些binary。

历史13b139b+5834ce5b的source38258403604/Build38258404288、a3b577f+e269d966的38255581451及general38255531407保留原向量。历史报告SHA `156cd314f670a3d958cea70beb3818a4ea3b6dba0d3e9d944e20b8d1858705da` 两仓原字节不变。38266821993、38258394875取消结果不计验收。general测试包中的旧发布JAR仍不能替代DV001当前native候选。

### DEVICE 当前回交与仍须完成的归并

App PR3@b180 已由CORE在原PR发布 [review5492931759](https://github.com/Goodwu/PiliPlusX/pull/3#pullrequestreview-5492931759)，正文REQUEST_CHANGES，GitHub状态COMMENTED。确认reopen facts、连接/响应头共享期限、成功累积buffer上限、两backup、旧revision写入拒绝等改善；本机JAR误提交已经撤回，不重复列为当前缺陷。但新revision/cid/baseUrl缓存键未接通仍读spec.key的selection，成功嗅探也不能授权真实126；HTTP成功体停顿仍可无限等待、错误take按chunk计数，in-flight Set不共享等待会使新serial发布空facts。本地source分流前videoUrl!及完整签名URL日志、DOVI轨道绑定/BL/RPU/颜色兼容冲突仍未修。284/analyze0只提供本机日志路径，未获CORE原始证据核验；dd76 hosted在routing SHA门失败、下游skip，07953取消，b180构建取证时运行中。debug包身份变更须与产品集成范围分开说明。

PR6@9a2已移除DIAG并修正AVC/nv12/copy fixture；[review5492587336](https://github.com/Goodwu/media-kit/pull/6#pullrequestreview-5492587336)仍为REQUEST_CHANGES，跨轮guard不可达及“FIRST complete sample”擅自收窄契约未解决。用户关于临时诊断范围和最终plan履行/真实切换验收的两项决定保持未决，CORE不放宽既有断言。旧“126出图”已撤回为120残影；新的DEVICE HEVC/P8.4画面报告不替代当前完整native/JAR/APK/轨道/代次/PTS/持续播放验收，不写成仅剩LG复测。

**DV001与PR5完整native、产物、设备归并必需且未完成。** 无新配方修复或移交；DEVICE仍在原PR单写符号读取失败闭合、双Vulkan独立全组合、失败传播/原子处理、干净staging、精确成员及真实链接/patch/NDK/helper/JAR/APK来源。批准native ledger仍空，失败关闭保持。PR5公共matrix和历史审查已部分归档，27项为synthetic/mocked；三个provenance banner保留；两个shell recipe继续排除。

### 接续与不可混用的验收层级

提交、推送并回读本阶段后，先取新SHA的Web定向/完整suite结果；一般CI中未终态的旧run持续按各自向量取证，过渡进度发PR4，不为轮询频繁改文档。随后按认领推进无需用户决策的独立代码或复审。原DEVICE的App/sniffer/gather/native配方不并写；普通Session、owner/carrier、生命周期、HDR与持续性能均仍必需。query/DASH/unknownDV/F01/R01/FFmpeg/config/SDK/source CI已有实现不按旧planned重做。experimental默认false，true主验证并回归false；LG YUV8/FULL/range1、精确设备门与owner/ACK/lease不变；10-bit/lease融合延期。

规范证据索引：`Goodwu/media-kit:docs/plans/core-web-shuffle-cow-checkpoint-20261012.json`，包含五份逐字节冻结报告：新App source、Build、库source、Web静审、DEVICE b180复审；各自的SHA256/字节数/source blobs和限制均独立记录。


### 2026-10-12：Web COW检查点之前的Current State（历史快照）

唯一公共集成分支 `routing/MK-ROUTING-20261011`；新 CORE 已接手，登记 [6126383144](https://github.com/Goodwu/media-kit/pull/4#issuecomment-6126383144)，范围补充 [6126444208](https://github.com/Goodwu/media-kit/pull/4#issuecomment-6126444208)，复审回交 [6126499419](https://github.com/Goodwu/media-kit/pull/4#issuecomment-6126499419)。CORE 唯一公共集成；现有 DEVICE 继续原 native/实机与 PR3/PR6 修订，不新增 DEVICE 工作线。所有主 PR 保持 OPEN/DRAFT、未合并、未关闭、未发布。

本检查点写入前重新回读：App `13b139b797aa65d853cafb5cb207d17a6e7aceac`；media-kit `5834ce5bdbd0bee3c2f7c130db0c05ed5f01f45f`；FFmpeg `9aba43cfbee182ade060cdccbe15340a0fbe3e83`；DV001 `1095a43acb4d0973b8bca59c5da4e300657bdb29`；PR5 `dc41787082752f234fed85db7fb7be3bd855cc45`；库 PR6 `0fb163c6ec8d54c46698227175b9a21468605246`；App PR3 `15551ede06b0cbec859d61e6d16f8dba2054bba1`（生产增量 `a2478d04`，后一笔仅档案）。这些是受审/受验输入，不是本次随后文档提交的 SHA；新提交不得借用旧 run 改标通过。

已核源码中的 query/DASH/P5/P8.4/unknown DV、CORE-F01、失败感知 SDR 兜底、FFmpeg e8df200c、CORE-R01 资源/decoder/copy/software 契约、有效 auto/prefer/require 和 SDK/source/CI 接线；LG config claim 回归也已修。保留完成记录，不按旧 planned/pending 或“34 info”重做。产品 experimental 默认 false，true 主验证并回归 false；LG YUV8/FULL/range1、精确设备门、owner/ACK/lease 保持，10-bit 与 lease 融合继续延期。

### 已核验的 CI 终态与层级

| run / attempt | 精确源码 | 终态及可证明范围 |
| --- | --- | --- |
| App source [38258403604](https://github.com/Goodwu/PiliPlusX/actions/runs/38258403604) / 1 | App `13b139b7` + media-kit `5834ce5b` | SUCCESS；6 jobs。四平台各 Flutter 268、analyze 0；Python 504 pass + 2 skip = 506；Dart/assets bundle 成功；Chrome DOM 1、Web build 成功。 |
| App Build [38258404288](https://github.com/Goodwu/PiliPlusX/actions/runs/38258404288) / 1 | 同上，但有本 run 独立 jobs/artifacts | FAILURE；7 success / 6 failure / 2 skipped。Android/Pink 在 selection 门因 selected manifest 为空停止，commands=[]；macOS/iOS/Windows x64/Linux x64 为 SOURCE_PREPARED_NATIVE_BLOCKED。批准 native 候选为 0。 |
| media-kit general [38255531407](https://github.com/Goodwu/media-kit/actions/runs/38255531407) / 1 | run head `e269d966`，实际测试 checkout 为 merge `811c7ba6`（main `d7619227` + `e269d966`） | FAILURE；22 success / 1 failure / 1 skipped。Web 60 pass / 1 fail / 27 skip，仅 player-set-shuffle；Linux、Windows 各 81 pass / 16 skip；macOS 88 pass / 15 skip。 |

本轮实际读取 24 个 ZIP（独立 source 5、Build 11、general 8），全部 bytes/size/API digest 匹配。16 份 source/Build bootstrap 均 fresh-source-only、57 步 exit 0、同一向量；独立重算 App lib/test 1442 + media-kit 全 tracked 1263 = 2705 项源码 SHA256 全匹配，261 个 package roots 中 10 个 media-kit 包均在当次 checkout。iOS 1918 个 base 文件已核，恰好两个批准变换经独立 patch 重放匹配；bundle 成功后 native 门停止，未开始 Xcode 构建。归档没有完整 kernel/Web 输出 bytes，不声称独立重算这些编译产物。

general 的八个测试 app artifact 确实存在并已检查内部成员；Android arm64 构建实际下载旧发布 v2026.013 JAR（mpv d24c59905 / FFmpeg b4d2ea4 世代），不能当作 DV001 当前 native 或 App Release 通过。App source `38258394875` 已 CANCELLED，排除。历史 `38255581451` 只证明 App `a3b577f3` + media-kit `e269d966`，原报告 SHA256 `156cd314f670a3d958cea70beb3818a4ea3b6dba0d3e9d944e20b8d1858705da` 保持不变；上一 Build `38255582037` 仍是失败关闭。此前库 source/query/Darwin 成功和 OHOS unsigned HAP 仅保留原向量/原层级历史证据。

### DEVICE 回交及必须保留的剩余范围

DV001 仍 `1095a43a`，PR5 仍 `dc417870`，没有新配方修复回交。review5483753705、comment6110373174 等要求继续开放：符号读取失败必须拒绝、两个 Vulkan 符号单独/已 weak/均无/工具失败/坏 ELF 等完整覆盖、失败传播、原子失败处理、干净 staging、精确三库成员、真实链接输入/patch/NDK/helper 及最终 JAR/APK/member 哈希。DEVICE 在原 PR 单写，CORE 复审；批准输入 ledger 保持空。

PR5 公共 matrix 已集成，27 项仅为 synthetic/mocked 回归；历史文档及 DV003/DV004 审查已部分归档。三个 provenance banner 本分支继续保留。`assemble-jar-arm64.sh` 与 `matrix-device-build.sh` 继续排除，不作为批准 recipe；本次只纠正 inventory 的 65 位 digest 笔误，正确值 `bf54737f08351c71877e2257beb8c6031e7a7aed754b26ceb64ddec0222b498b` 对应 PR5 blob `33abc719` 的 2578 原始字节。**DV001 与 PR5 的完整 native、产物、设备归并都是必需且未完成的范围。**

库 PR6 / DV004 对 `0fb163c6` 的 [review5492283452](https://github.com/Goodwu/media-kit/pull/6#pullrequestreview-5492283452) 结论为 REQUEST_CHANGES：partial 轮在写 identity 前返回，首个完整轮又立即返回，跨轮 guard 实际失效；最终 route/hwdec 比较不能证明真实组件未切换。新 fixture 混用 AVC identity 与 HEVC/MIME、copy 路线与 hardware pixel，仅 gather 返回不构成 Session 验收。用户关于临时诊断范围和“最终 plan 履行／捕获任何真实切换”的两项决定继续未决，不擅自放宽断言。

App PR3 / DV003、DV005 对 `15551ede` 的 [review5492283684](https://github.com/Goodwu/PiliPlusX/pull/3#pullrequestreview-5492283684) 同为 REQUEST_CHANGES。首次/refresh hint 已接线，应改记部分修复；intent.reopen 仍漏 initialDoviFacts。HTTP 总 deadline/流式字节上界、按源身份隔离缓存及竞态、视频轨道绑定/颜色和层冲突仍开放；新 playerInit 无条件 `Uri.parse(videoUrl!)` 在本地分流前可抛空值异常，完整签名 URL 日志需收敛。这些 review 的 GitHub API 状态为 COMMENTED，正文结论为 REQUEST_CHANGES，不冒称正式合并保护状态。

DEVICE [6126388894](https://github.com/Goodwu/media-kit/pull/4#issuecomment-6126388894) 已撤回旧“126 出图”为 120 残影/切换未发生，真实 126 原先在 decoder 创建前被 sourceMetadataUnknown 阻断。新的 DV005 HEVC/P8.4/verified/连续画面及本地测试声称仅按 DEVICE reported、CORE 原始证据待补登记；不能据截图文件名、旧 AVC 序列或只改档案写成仅剩 LG 复测。14:45:42 UTC 补核 PR3 Build38263795883（a2478，attempt1）终态 CANCELLED、Build38263881419（15551，attempt1）FAILURE；两者 source 子作业均在 routing App HEAD 与 DEVICE EXPECTED_APP_SHA 一致性门退出，Flutter/Python/bundle 均未运行。PR6 精确0fb163c6 的 Actions 查询仍0个 run；186/775测试尚无独立 hosted 背书。general macOS 的88通过为最终汇总，日志含字幕重试和 OutstandingWork 失败历史，不能据终态抹去。

最新 DEVICE [6126637477](https://github.com/Goodwu/media-kit/pull/4#issuecomment-6126637477)（14:48:40 UTC）组合终审也为 REQUEST_CHANGES，确认 HTTP/cache/reopen、跨轮契约与 fixture 阻断，并要求移除 DIAG 后新 SHA 复审；其 B4 另报旧 dv003 Flutter/analyze 日志实为223pass5fail/undefined_identifier，需补受审 SHA 的真实成功日志。该 reviewer 报告新 LYA126 HEVC/P8.4 两帧有效；此是已读回交结论，公开评论未提供原始日志/截图字节及完整 native 向量，CORE 独立产物验收仍待。DEVICE 已声明继续原分支按库 PR6→App PR3 修订；本 CORE 不并写。

### 接续范围与证据

本检查点仅更新 TASKS、唯一 conversation 和 JSON 证据/当前台账，未修改生产函数、CI/SDK 或 native recipe。原用户 checkout 的 dirty/untracked（含 App `.zcodeignore`、FFmpeg configure）均未触碰；本 CORE 使用独立干净 routing clone。当前 Linux 环境具 Git/Python/Node 及字节取证工具，没有本地 Flutter/Dart/ADB/native SDK；测试结论来自实际 hosted run，不冒称本机/实机执行。

提交、推送、回读此检查点后，下一候选 `CORE-WEB-SHUFFLE-01` 才登记写范围：Web `real.dart::setShuffle` 与 `player_test.dart` 两个 shuffle 用例/已发 Playlist 快照回归。可变列表原地改写并被 stream distinct 吞事件是源码候选，尚非已证根因；先确定性复现，再评估启用/恢复分支的局部 copy-on-write，验证 Chrome 定向和完整 Web 包。共享 Session/planner/backend/realizer/output slot、App hdr_output/controller、CI/SDK 仍不在本 CORE 代码认领内。

native 之后还须同向量验普通 Session、实际 owner/carrier、生命周期、最新 P5/P8.4 true/false、实体 HDR 和持续性能。各层分别验收，不因宿主、bundle、旧 APK 或部分文档归并而结项。完整证据索引：`Goodwu/media-kit:docs/plans/core-successor-checkpoint-20261012.json`；三份 CI 报告 `core-successor-app-source-ci-20261012.json`、`core-successor-app-build-ci-20261012.json`、`core-successor-general-ci-20261012.json`，以及 native/PR3/PR6/字节来源/source index 均有独立 SHA256。


### 2026-10-12：CORE successor 更新前的 Current State（历史快照，已被顶部取代）

唯一公共集成分支 `routing/MK-ROUTING-20261011`；CORE 是唯一公共代码和审查集成者，DEVICE 继续原 DV001 native recipe/build/device acceptance。最新回读 heads：App `a3b577f3794634b497c6f82369bcc98d39d91fa2`，media-kit `e269d9669becb5812663200e7521901e8254c8bd`，FFmpeg `9aba43cf`；DV001 PR #1 `1095a43acb4d0973b8bca59c5da4e300657bdb29`；PR #5 `dc41787082752f234fed85db7fb7be3bd855cc45`。主 PR 均未合并、关闭或发布。

query/DASH/unknown DV/F01/R01、auto/prefer/require 有效配置闭环、FFmpeg e8df200c、失败感知 SDR 兜底等已实现项保持完成。旧“34 info”不再是待修债务：App source run 38255581451 四平台 analyze 均无 finding。experimental 产品默认 false，true 主验证、false 回归；LG YUV8/FULL/range1、精确设备门、owner/ACK/lease 保持，不重开10-bit与lease融合。

App run 38255581451 attempt 1 对准确向量 App `a3b577f3` + media-kit `e269d966` 为 SUCCESS：四平台 Flutter 各 268 项，analyze 无问题，Python 504 pass/2 skip，Dart bundle/source freshness 通过；artifact ZIP/API digest、source.txt、57步 fresh receipts、前后 source vector 和十个 package roots 已核验。证据 `docs/plans/core-source-ci-a3b577-e269d-checkpoint-20261012.json` SHA256 `156cd314f670a3d958cea70beb3818a4ea3b6dba0d3e9d944e20b8d1858705da`。App Build run 38255582037 失败关闭于 native input acquisition/selection gates，没有可验收 native/APK 产物。

media-kit source run 38255531539、query 38255531454、Darwin 38255531401 成功；OHOS run 38255531417 为 unsigned HAP hosted build，不代表设备验收。general run 38255531407 最近一次核对仍运行，继任者需读取终态。

PR #5 已部分归并：公共 matrix 功能已进入库，27项是 synthetic/mocked 回归。DV003及新 DV004 critical review 作为历史审查按 source commit/blob/SHA 记录；DV004为 REQUEST_CHANGES，两项决定待用户方向，不据归档启动实现。最新 PR5 `dc417870` 的 `assemble-jar-arm64.sh` 与 `matrix-device-build.sh` 源码哈希已记录但不导入/执行：前者仍有 nm 读取失败误放行且只检查一个 Vulkan 符号；后者为硬编码重复配方并删除 build intermediates。PR5 merge `66aa28e` 冲突解决移除三份先前导入文档的 provenance banner；本分支保留，并在 `DV-BUILD-01/import-manifest.json` 记录差异。PR #5 与 DV001 的完整 native/产物/设备归并未完成。

DV001 PR #1 仍在 `1095a43`，无 DEVICE 新修复回交。review5483753705、comment6110373174、6111479264、6111836233、6112842188 中的读取器失败闭合、两个 Vulkan 符号分别覆盖、失败传播、clean staging、精确三库成员与真实链接来源/patch manifest 要求仍未关闭。DEVICE 在原 PR 单写；CORE 不接管或另写配方。

PR #3 DV003 仍为 Critical REQUEST_CHANGES，不原样归并，也不开第二 DEVICE 线。继续验收需最新 native producer 输入、APK/ABI/签名来源、普通 Session 和实际 YUV carrier/owner、P5/P8.4 true/false 与可见 HDR/持续性能。宿主 CI、bundle、native build 和设备显示分别报告，不互相替代。

### 2026-10-12 TASKS 旧状态快照（历史）

## MK-ROUTING-20261011（CORE继任，2026-10-11）

- 当前已核对源码向量：库751d0cdd + App6c4c1b478。库CI38168100713 video772+3原mac Linux跳过/lab298/两strict0；App38168113931 SUCCESS及Build38168114089内四平台各268/strict0/bundle/finalize，hosted Python实际两次444、parser/kernel7与身份前后稳定。Build整体六Release仍失败；Android/Pink空accepted selector实际preAPI/preGradle拒绝，非native通过。精简证据docs/plans/core-native-ci-checkpoint-20261012.json；原失败/旧向量保留。

- 状态：进行中；唯一集成分支 `routing/MK-ROUTING-20261011`，主PR media-kit#4/App#1/FFmpeg#1；context=`archives/conversations/media-kit-routing-20261011.md`。主PR不自动合并或发布。
- 当前推送源码：库a31269ba + Appabc149；FFmpeg9aba43cf。CONFIG模型检查点独立35库/22App/4额外反例与target strict通过，实际DASH/planner/Session/report同一配置闭环仍未完成。
- CORE-F01、DASH逐候选过滤、query迁移及FFmpeg e8df200c已完成，不重新开发。旧6e757+569138的192Flutter/34info属于历史向量；34info已在CORE-CI03清零。
- 最新完整App源码验证：08acc+8b98 source38160661703四平台SUCCESS，各211Flutter/strict0/bundle/来源/freshness，实际359Python；Build38160661882六Release仍FAIL。新abc149+87eb CI06 source38161696564四平台SUCCESS，各233Flutter/strict0/bundle/finalize/来源与freshness；Build38161696805源码矩阵SUCCESS但六Release失败，Python本轮各359；库source38161681107 video663+3原mac Linux跳过/lab298/两strict通过。不得跨向量重标。
- R01a/b/c/d/e已提交保留。CONFIG实际DASH/planner/Session/report同快照、实际require履行和串行停止/cleanup重试已宿主V2 PASS：库v3作者762/独立774/strict0，AppR1作者268/strict0/bundle/独立90+1，20/16hash一致。准确CONFIG切片已集成push/readback，最新组合CI、native/设备验收与DV001/PR5整体归并仍开放。
- DV001与PR#5必须完成归并：PR5 86c三Markdown与5b279611追加16行已分别归入e162/aeaf并独立原文/hash/链接核验；两个配方脚本未导入，不能标整项完成。2026-10-12本轮重新读远端，DV001仍1095a43，PR5仍5b279611。DV001原review5483753705/6110373174未修，DEVICE继续原PR单写，CORE审查整合。
- DV001剩余门：符号读取失败关闭、两Vulkan目标独立检查、构建失败传播、干净staging、最终成员/链接/补丁来源；需受审完整manifest及最新适用源码产物。旧8bed+a3+JARcd5的188/34info/244仅DEVICE声称，AVC EOS不能代替dvh1/HDR验收。最新P5/P8.4、experimental true/false、普通Session与可见输出/持续性能仍必需。
- native输入gate08acc独立critical通过；CORE接受账本空。Android/Pink实际Release接线作者114/全Python412通过，但V2确认新增res/assets/shaders/jniLibs输入漏检阻断，原writer第一轮修复中；未获受审输入必须明确阻断，不用旧默认JAR。Windows完整bootstrap已解阻，旧PNG唯一因果未证明。actualYUV carrier/owner arm仍DEVICE范围；产品experimental默认false不变。

- General长suite旧两向量已取消且日志持续推进，无挂死证据；ci.yml仅本任务routing分支保留live运行，其他分支取消策略不变。三处旧action已迁移checkoutv4/softpropsv2并完整actionlint通过；不推定general通过。

### 2026-10-12 macOS 前置整合前状态快照（历史）

#### Archived Current State（历史快照）

唯一集成分支 routing/MK-ROUTING-20261011。本轮push回读远端 Appa05dfe1bea85e78a7b214b0e4044eab7902a3e06、库38ffb72920550d76c41948daa56aa01b4393681d；FFmpeg9aba43cf、DV0011095a43、PR5 5b279611仍按各自证据归属。root唯一公共集成者，DEVICE继续原native配方/构建/实机职责。所有主PR未合并、关闭或发布；未知dirty和恢复材料保护。

query/DASH/未知DV/F01/FFmpeg e8df200c、R01依赖与资源契约/decoder复核/有限copy软件路线、有效auto/prefer/require及代次/清理债务已实现，禁止按旧planned重做。App34info已清零；产品experimental默认false保持，主验证true另测false；LG FULL/range1/YUV8/精确设备/ownerACKlease保留，不重开10bit/lease融合。

已完成源码验收的历史组合1970+d916：独立source38172589162 SUCCESS，Build38172589627 FAILURE但嵌入源码矩阵API均SUCCESS。独立四平台归档已逐ZIP SHA、source.txt、真实57step/bootstrap、10包当前根、before/after/final源码新鲜度核完；桌面三平台strict No issues/Flutter各268/实际bundle命令成功与kernel摘要。主Android源码日志268 Flutter+Chrome1/strict0。独立Python479总计、477成功、2 iOS真实SDK用例因缺shared Flutter Git source跳过（201.015s）；7真实Dart YAML/parser receipt已核。嵌入Python日志479总计/216.190s，未将独立skip详情套用。6 nativeRelease失败、parity跳过，不称全绿。中央精确归档证据6113706863；旧e31+d916的451与库772+3/lab298分别保留不重标。

Linux/Windows已有A源码前置仍准确SOURCE_PREPARED_NATIVE_BLOCKED，历史e31 Release verify步骤也实际bundle成功（旧错误已更正），不等于native。Android/Pink批准ledger仍空，preAPI/prestaging/Gradle拒绝，不借发布JAR。各平台native、generated产物完整来源、实际设备/HDR/持续性能仍缺验收。

iOS六文件已1970准确提交/回读，第二修正Critical PASS_WITH_SCOPE。独立clean1970+d916/private SDK真实iOS bootstrap/sourceverify/finalize已57step exit0/fresh-source-only；原variant因磁盘不足未启动，旧diskblocked记录保留。空间恢复后原1970+d916真实prepared快照经独立确认合法续接，prepare（含实际offline/enforce pubget）、额外offline/enforce、prebuild、sourceverify、variantlock、finalize全部exit0/finalized，r2 checkpoint 0aacec76已独立回读 PASS_IOS_VARIANT_SOURCE_PREBUILD_ONLY，12实际阶段/1897文件/31pub生成/3build生成/86links/261包清单均核；core-ios-source-r2-evidence-review-20261012.json为95621b42完整独立报告。直接fresh绑定prepare的真实失败r1保留，未手工改status。此通过仅源码前置，不含bundle/Xcode/native/device。新SDK/newcache不能当原Android cache改标签；未运行Xcode/native。

Linux B最终R2九文件V2 PASS_WITH_SCOPE，19实际测试+14独立micro probes；逐requester ORIGIN与全部DSO ABI门恢复，unknown generated明确unbound，fullBundleProvenanceVerified=false/releaseVerified=false。未重跑本轮完整acquire→CMake链，真实producer/编译链接/运行未验，生产ledger仍空。精确文件hash与范围保存在core-linux-native-consumer-final-review-20261012.json；已于库3817b8f3/Appdb6df51e提交并推送，九source committed blobs同V2冻结；不能扩大native批准。

DV001与PR5必须完整归并。历史三MD已归台账；公共matrix归唯一tool入口，重复JAR bundler归原DEVICE canonical，不复制第二配方。PR5四文件第二修正因ENOSPC未完成，PR5公共矩阵四文件最后R4 V2 PASS_WITH_SCOPE，27tests独立通过；92包/37生成正常，SDK真实asset bundler与隐式2.0x/prefix3x变体成员一致，变体新增/删除/内容/mode/link变化可检出，正常Gradle build输出未误冻结，SDK内部链接目标闭包已关。源CLI、源/SDK/资源/七SO/独立artifact批准/每APK来源签名/失败传播公共功能归唯一tool入口。已库38ffb729/Appa05dfe1be准确commit/push/readback，四matrix committed blobs同R4冻结，两个repo源切片clean；原SDK/资源/PUB生成三轮失败与ENOSPC材料保留；未运行新precache/pubget、真实八APK/native或设备。八实际APK/四源truefalse/普通Session/owner实际carrier/可见HDR性能未完成；DV001符号读取失败、两个Vulkan目标、失败传播、clean staging、最终成员/链接补丁来源仍需原DEVICE修复。

用户授权只移除已核旧cache重复文件。固定100小批次经V2与remote PREPARE6116072490持久化后，仅4项实际删除；第5项与前项旧hardlink共inode导致nlink/ctime变化，严格STOP，余96保留。新cache/donors/SDK/App/库全后验相同。实测释放85,913,600bytes，随后系统释放不能归此次清理。原runtime远端log超时失败保留，PARTIAL重试已6116651070双API回读通过；raw checkpoint /tmp/mk-ios-cache-delete-partial-checkpoint.json与恢复材料保留。清理结束，不继续删除。实际角色容量错误已记录并续接原角色，禁止换generic/directlauncher。

新实际CI捕获6d349a06+3817b8f3：Appsource38243549009及库source38243502467已success并独立8artifact实SHA回读：App4平台各268/0skip、Python499=497成功+2原iOS缺共享SDK跳过、WebDOM1；库video772成功+3mac专用Linux跳过/lab298/audit6+12。AppSDK3.47.2与库3.47.7分开。Build三个Release源码前置已独立PASS_HOSTED_RELEASE_SOURCE_PRELUDE_ONLY：57step/bundle/finalfresh真实成功，iOSvariant1909files/31+3gen/86links/261manifests/仅2Dart转换一致；唯一失败均native-input-unavailable，不等Release/native/device通过。两份6d349-checkpoint JSON保全新证据，Build其他矩阵终态待另核。iOS routing workflow三文件已6d349a06提交/push/十二source blobs合并回读同V2；已有50作者contracts及限定独立复审，独立完整重跑ENOSPC未通过。下一步：回读新CI，完成PR5剩余复验/V2及准确stage/commit/push/readback；保留各源码向量，后续HEAD前进重新验收。Linux完整producer→consumer→generated bundle、iOS routing workflow/native、Windows native/其他Release和DEVICE同线程协作继续，不因源码绿或正确拒绝结项。

PR5原matrix-device-build.sh功能归现tool/matrix-build.sh + routing_matrix.py，原assemble-jar-arm64.sh重复配方仍归DEVICE DV001；此是脚本功能归并，DV001未修复/未回交且八包实机未验，因此整项仍开放。

新适用组合a05dfe1be+38ffb729复验已启动：库source38250657319，Appsource38250698262/Build38250698496（排除同SHA cancelled38250692692），未重标上一6d349+3817结果。



### 2026-10-12 A hosted终态前阶段记录（历史）

唯一集成分支 routing/MK-ROUTING-20261011。已推送源码：media-kit 751d0cdd69c26374d452fbf672c5600ce59f2387；App当前e31aee1b09d6658dadd79a58a19bb1c097a57161（旧已验源码向量6c4c1b4787fe2ce5459ee1d775279192fe432416）；FFmpeg 9aba43cfbee182ade060cdccbe15340a0fbe3e83。DEVICE DV001 1095a43、PR5 5b279611 最近回读未见新修复；中央登记6112985520/构建PR6112842188。主PR未合并、关闭、发布，原checkout未知dirty保留，root唯一公共集成者，DEVICE继续唯一native producer/实机责任。

已实现并集成：query/DASH/unknown DV门、F01源事实、FFmpeg e8df200c、R01输出资源契约/实际decoder复核/有界独立copy软件路线、有效auto/prefer/require从App到Session报告及配置代次/清理债务。CONFIG后续LG专用claim回归已修并V2通过。experimental产品默认false；true主验证、false回归；LG FULL/range1/YUV8、精确设备门和owner/ACK/lease保持，不重开10bit/lease融合。

上一完整联合验收向量为751d+6c4，下列381681证据仍只属该向量。当前e31aee1b0+d9163940 source38169989794已SUCCESS：四平台各268/strict0/bundle/finalize、Python实际451（177.586s）及7parser身份/真实kernel；Build38169989974仍有macOS/Python两source jobs活跃，六Release已失败，暂不声明整轮Build矩阵终态。库source38168100713 SUCCESS：video772、3项原macOS专用Linux跳过、lab298、两包strict0；query38168100554和Darwin38168100584成功。App source38168113931 SUCCESS：四平台各268 Flutter、strict0、bundle/源码绑定/finalize；Python本轮实际444，真实Dart/YAML/kernel 7项与前后identity通过，不借旧362。Build38168114089已completed/failure；其独立Python本轮实际444。34info已清零并由当前严格分析验证。Build内四平台各268/strict0/bundle/finalize均真实成功；完整证据720文件索引已收尾，精简摘要docs/plans/core-native-ci-checkpoint-20261012.json，不以源码通过代替native/设备。

Android/Pink已集成来源/真实YAML/生成物及插件精确清单、双artifact/accepted-ledger、实际localJAR/ABI/sign/parity/finalize门。当前接受账本空；最新两Release实际bootstrap成功后在空selector门失败（artifact11712449501/11712224176，commands=[]，preAPI/preGradle），不能宣称native候选通过。当前独立clean最新源码完整prepare验证进行中：原共享SDK36个tracked修改已正确拒绝且保护；新独立clean SDK d3b14与2524 cache成员hash核对，废弃symlink缓存保存p-rejected，空私有cache真实pubget通过。正式bootstrap及最终finalize exit0/fresh-source-only（receipt SHA256 6b261eff9516a60d1933e617770c3eaae017e2cef9babb4753c5bbba2fc05117）；Android/Pink真实prepare、offline lockedpubget、prebuild与routing lock均通过，分别inputs1888/pubGenerated31/buildGenerated3/pubLinks86，错误参数验证driver旧exit2仍保留。此证据只属于6c4+751，不是native/JAR/APK/device通过。旧receipt不得换vector重标。

DV001与PR5必须完整归并。PR5三历史MD与16行增量已入e162cb3c/aeafc6c3；两个脚本未导入。DV001原审查要求符号读取失败拒绝、两个Vulkan目标分别检查、构建失败传播、干净staging、精确最终成员/补丁及链接来源记录，仍由DEVICE在原PR修；CORE消费者验证不等于producer修复。最新源码P5/P8.4、true/false、普通Session/实际carrier/owner/HDR呈现/持续性能尚缺同向量native与实机验收，旧AVC EOS/模型SDR不重标。

当前工作：linux_windows_source_wiring唯一写App四个workflow/contract文件，接通同一vector/真实bootstrap源码前置，native缺当前输入时准确失败并归档，绝不以此称Release完成；platform_release_design只读设计Linux本地SO/headers/dependency完整消费者及DEVICE原recipe回交接口，随后接续真实producer→consumer→bundle；native_input_worker已完成当前clean Android/Pink完整prepare及finalize，归档收尾；ci_verify已完成当前CI证据核验（19 artifacts及准确ZIP hash）。root拥有TASKS/context/台账/Git。Windows/iOS及其他Release门、DV001/PR5和实机证据仍待，不因单项源码绿灯结项。

Linux/Windows A第二轮已独立Critical PASS_WITH_PENDING_HOSTED并提交推送App e31aee1b09d6658dadd79a58a19bb1c097a57161。43contracts/actionlint/20实际caller-context条件及pwsh失败传播通过；原direct dispatch绕过、提前prepared名称和首修误拒均关闭，原两轮失败证据保留。当前仍只源码前置，native缺接受输入阶段准确失败，hosted新增路径待验；Linux B消费者未审不入已验切片。

当前执行范围更新：A第二轮以routing-mode及完整两SHA判定已捕获输入，避免错误按caller event_name区分reusable；已Critical通过并推送e31aee1b0。ios_source_variant独占新增iOS variant/测试、patch.ps1仅SDKOnly隔离条件、bootstrap ios平台及对应测试，不动App原Dart或共享workflow；Linux B消费者独占CMake/独立Linux验证获取工具，接受账本空。PR5 matrix-device-build必要功能正只读定位现tool/matrix-build.sh归并接口，assembly重复打包仍由DEVICE修原DV001，不新增配方。

当前中央范围登记6113083125：pr5_matrix_integration独占库tool/matrix-build.sh/routing_matrix.py/test/README，归并原PR5公共矩阵能力，不改DEVICE bundler；ci_verify只读核Appsource38169989794/Build38169989974实际e31a+d916（source已真实success，Build最后两source jobs仍live，不提前终态）；iOS variant首轮冻结Critical拒绝后由原writer修正平台身份；Linux B实施中、尚未冻结审核。

Hosted A Linux最新实际证据：Build job114560490516 failure，artifact11713952189；真实prepare/verify/finalize各success、bootstrap fresh-source-only、57steps exit0、准确e31a+d916，随后SOURCE_PREPARED_NATIVE_BLOCKED，producerReceipt=null/inputRoot缺/native与device=false，旧production下载全skip。Release前置本身没有bundle步骤，bundle由独立source矩阵验证；先前“Release prepare/bundle/finalize”措辞不能作为该Release bundle证据。Windows还在核验。



### 2026-10-12 最新CI收尾前状态快照（历史）

当前远端集成分支均为 routing/MK-ROUTING-20261011：库751d0cdd69c26374d452fbf672c5600ce59f2387、App6c4c1b4787fe2ce5459ee1d775279192fe432416（已审CONFIG源码切片已提交/push/readback）、FFmpeg9aba43cf；DEVICE DV0011095a43、PR5 5b279611刚重新回读，无新修复回交。主PR仍未合并/关闭/发布。原checkout未知dirty保留。中央最新登记6112841982。

已完成F01/query/DASH/未知DV门/FFmpeg e8df200c，不按旧planned重做。34条分析info已在CI03清零；最新已提交联合源码CI06仅证明Appabc149+库87eb：四平台233Flutter/strict0/bundle/源码freshness，Python实际两次359；Build六Release失败，不能称native验收。库a312窄CI源码685+3既有skip/lab298/strict0、query实际Java31tasks+host34、Darwin9通过；OHOS为实际PR merge unsigned，不是实机。证据原各handoff/summary保留。

CONFIG实际闭环库v3与AppR1原冻结宿主V2 PASS并已集成push/readback，但后续完整lab CI证实LG单次实验配置禁改门回归，该LG窄修四文件已Critical PASS（独立lab298/video775/额外4边界、两strict0/hash同），新源码检查点已push/readback且提交树逐hash与复审同；最新库CI video772+3skip/lab298/strict0已通过，Apphosted矩阵与真实toolsCI收尾，native/实机仍未验。库20文件freeze af984d：作者762/strict0，Critical 762包内+12独立共774/strict0，前两轮三个P1真实修后绿、20hash前后同。App16vector47d60f9...绑定同库v3：作者268Flutter/strict0/bundle/channel11、独立90+1/20kwargs及hash一致，first文件设置竞态已关闭。能力查询/设置/refresh服从最新完整request与源代次，实际require履行复核及cleanup重试保留。requested/effective同配置已接DASH/planner/Session/report；未知legacy诊断、默认experimental=false及unknownDV/F01/owner/budget门保留。最新HEAD-only CI、native/实机仍未验，不把dirty宿主结果重标新SHA。各原失败日志与逐轮freeze/review完整归档见core-config-implementation-review/implementation-handoff JSON。

Android/Pink实际Release候选第二修复轮：第一来源漏项8注入已拒绝，但V2另证真实offline pubget正常ephemeral/plugin误拒与转义YAML build资源绕过且真实bundle包含，仍REQUEST_CHANGES。原native_input_worker单写variant/输入/workflows，新增持久Dart真实YAML工具及直接测试、精确pubgen/link契约；待实际Android/Pink prepare→pubget→prebuild正例与真实资源负例及新freeze复审。reviewer私有SDK/cache授权独占、packageconfig遗留共享roots只在私有metadata按逐包字节hash重绑，原证据保留，共享SDK不改。接受账本空，无approved A/B/新native/APK声明。

DV001与PR5必须完整归并。三历史MD与16行增量已分别入e162/aeaf并核原文/hash/链接；两配方脚本未导入，整体未完成。原DV001符号读取失败/两个目标各自/失败传播/干净staging/精确成员链接补丁manifest等审查仍待DEVICE在原PR修；CORE不另写配方。最新适用源码P5/P8.4、experimental true/false、普通Session/实际carrier/owner/HDR呈现/持续性能仍需同向量构建与实机验证，旧模型/AVC EOS不重标。LG批准FULL/range1/YUV8、精确设备门、owner/ACK/lease保持；不重开10bit/lease融合，产品默认experimental=false。

下一步按已有认领串行冻结、独立V2、准确stage/中文commit/push/readback及最新组合CI；余下Linux/Windows/iOS Release消费者与原DEVICE native协作随后接入，不用发布JAR/SO或旧pin代替当前构建。当前活跃子任务r01d_worker（库修复）、app_config_v2（App critical）、variant_boundary_fix（库独立反例/复核）、native_input_worker（第二来源修复），root唯一集成者。


最新general只读快照：a312 run38164066846已cancelled；旧5c8 run38162912132 GitHub仍in_progress、三test jobs运行且日志不可取，无法证明挂死原因。新docs HEAD作业pending/运行快照不推定终态。证据/tmp/mk-routing-ci-current-snapshot-20261012.json。


第二来源修复实际进展：真实App旧abc149只读解析/生成inventory 1879 tracked/31 pubGenerated/3 buildGenerated/86精确插件links通过；7 YAML语义与kernel编译通过，27 synthetic variant通过。仅工具/清单范围证据，不是新候选完整prepare/native通过。私有101包逐成员hash一致后metadata重绑receipt=/tmp/mk-routing-r2-private-sdk-rebinding.json；inventory=/tmp/mk-routing-r2-real-pubgen-inventory.json。资源真实bundle和错链/生成hash负例仍进行。


App第一修复最新10个真实variants通过，覆盖firstfile/真实FileSource/no-page/latest设置/公开新sourceB优先/dispose/三个真实清理债务；observer仅testing生产factory不传。现对库v3冻结组合fresh全Flutter/strict/bundle，未终审/提交。来源第二修复35variants与30workflowcontract/actionlint通过，普通tracked资源真实bundle exit0且字节匹配、escapedbuild资源在构建前拒绝；全Python与真实Android/Pink诊断收尾，完整新candidate prepare仍待CONFIG真实提交。


2026-10-12集成切片：仅各冻结CONFIG源码/tests（库20、App16）+TASKS/context/本阶段handoff；Android/Pink native16文件仍dirty等待第二来源修复Critical V2及最新clean完整prepare，不混入CONFIG提交。


实际新CI capture已确认source38166934942与Build38166935298 attempt1均Appb7d3a8efa+libb5c50670；本轮Python实际两次362通过（31.293/34.451s），其余矩阵仍live/queued不推定通过。Darwin38166919514九项成功；source/query/OHOS仍live、generalpendingnojobs。

独立来源复审在最新b7d3gitarchive实际offlinepubget/清单正向通过（1881tracked/31pubGenerated/86插件）；仅清单，不完整prepare。hostedPythonjob缺真实SDK是确定新增CI阻断，交Lead/只读Specialist做窄provision方案，native16冻结未commit。


最新CONFIG源码CI真实阻断：库source38166919509 video759通过+3既有skip/strict0，但lab267通过2失败：fake Session.open缺options override编译失败；LGsingle-open wrapper失败后setPreference应拒却返回（专用token pre-mutation guard被CONFIG遗漏）。独立b5c隔离17pass2fail已复现，lab_config_regression唯一writer获窄增Session三个setter禁改门与claim先消费后解析（扩展需红例）及直接tests，普通无tokenCONFIG事务不封锁；需新Critical复审/新提交CI。App已实际Linux两job268/strict0/bundle/finalize、BuildAndroid268+Web成功，其余Windows/macOS仍live不推定通过。OHOS新HAP为PRmerge9e5577d5非纯b5c。

第二来源修复Critical 140及最新b7d3清单/所有YAML资源/插件反例PASS_WITH_SCOPE，整体REQUEST_CHANGES仅CIprovisioning；新native_ci_sdk_wiring唯一三文件（workflow/parser test/contract）按Specialist方案保留macOS fullsuite、双exactcheckout+现bootstrap、真实receipt前后identity/finalize/失败归档，不skip或新SDK配方。native其他13冻结文件不动，当前未提交。


最新待集成切片已通过独立审核：库LGguard四文件+记录（readonlytoken专用setter pre-mutation、失败claim在解析前消费、fakeoverride同步；无token普通Session不封锁）V2 PASS；App native16来源scopePASS+3CI窄修V2 PASS_WITH_PENDING_HOSTED，444Python/36contract/7Dart与identity/actionlint通过，接受账本空、不批准native。源码切片逐hash核对后唯一root提交/push/readback，最新hosted/完整prepare仍待。


最新实际组合CI capture source38168113931/Build38168114089 attempt1均App6c4c+lib751d。库source38168100713已SUCCESS（video772+3skip/lab298/两strict0）。Android/Pink真实Releasebootstrap成功后在accepted acquire阶段拒空manifest：artifact11712449501/11712224176、reason missing-accepted-native-input、commands=[]，preAPI/preGradle，不是旧cache/pin，不代表native成功。MAC Python job实际bootstrap中，不能提前叫444通过。

已复读DEVICE DV0011095/PR5 5b279 HEAD+最新评论，无新修复回交；中央6112841982及构建PR6112842188同步当前实际源码检查点/消费者合同，请DEVICE继续原recipe回交当前stage/精确阻塞，不新增DEVICE任务或配方。最新完整clean Android/Pink sourcevariant prepare验证另进行，真实bootstrap新receipt必须由最新源码与干净sourceSDK在独立环境生成；r3旧patchedSDK/receipt不得改vector冒充，private工具pubget允许按正式现流程执行，共享.runtime只读。



### 2026-10-12 CONFIG独立反例前状态快照（历史，已由Current State替换）

当前已推送库a31269badbf8ecc9ec286a1b0c4bf4f6639708ef（R01e与两CI检查点；CONFIG仍dirty） + Appabc149dcf7e89cf0ea1f08ba133bf1047c36138d；FFmpeg9aba43cf；DEVICE DV001仍1095a43。最新两个CONFIG提交仅事实模型/纯adapter检查点，V1独立35库+22App+4额外反例/target strict通过，一行public export；requested/override/effective与来源/序列化、explicit reset、默认experimental=false与legacy诊断保留。模型未接实际DASH/planner/Session/report，不能标auto/prefer/require闭环，未知hwdec诊断必须由caller处理。库handoff=docs/plans/core-config-model-handoff-20261012.json。

最新完整已验向量只为App08acc+库8b98：source38160661703 attempt1四平台真实bootstrap SUCCESS，各211Flutter/strict零问题/bundle/finalize/10routing+261roots+102toolsroots/2662源码hash/前后freshness；Python359/Chrome1/Webrelease成功。Build38160661882源码矩阵全成功，整体因6Release前置失败。库source628video+3既有mac Linux跳过、lab298及两strict/query/Darwin9/OHOSunsigned通过。Windows原SDK状态干净已真实解阻；旧PNG唯一因果未证明，旧b197取消partial不重标。general旧8b98四平台test仍live/log API404，不猜阻塞/通过。CI05证据/tmp/mk-routing-ci05-20261012/summary.json。

CONFIG组合CI06终态：Appabc149+库87eb，source38161696564 attempt1四平台SUCCESS，各233Flutter/strict0/bundle/finalize，8份source及Buildsource receipt的2667源码hash、10routing/261allroots/102toolsroots无逃逸、originalSDK状态空、准确tree498a895e/c4320051及freshness一致。Python实际两次359，Chrome1/Webrelease成功。Build38161696805源码矩阵全成功、整体因六Release失败；库663video+3既有跳过/lab298/strict及query/Darwin9/OHOSunsigned通过。general仍仅四live快照不推定通过。全部artifact/ZIP/hash/logs证据/tmp/mk-routing-ci06-20261012/summary.json，不重标R01e新提交。

R01a/R01b/R01c/R01d已提交并分别验证。R01e17文件已冻结，作者及独立V2各688全包/strict No issues通过，17源码/test哈希一致，4作者撤门及4独立外置反例证据保留；最终V2 PASS仅宿主范围已回读，本轮保存检查点。有限SDR Texture direct/copy/software、完整route去重、共享MC解码失败与不同导入/upload失败区分、实际CPU帧复核、requested/attempt/effective报告及caprefresh保留当前已审路线已接真实Session。默认coordinator上界1，Session有限catalog3，不放宽HDR<=2/nativeonce/source一次/owner清理债务；F01和unknownDV颜色门保留。普通源EL假fixture修正来自native属性仅DOVI可用的事实，未改变生产源模型。handoff=docs/plans/core-r01e-handoff-20261012.json；不证明native/实机/YUV presenter。CONFIG继续修不可满足新约束却旧输出继续及同route新require实际复核。App实际接线认领中央6112094797/6112101005，与Release writer分离；库共享写入待R01e提交后串行。

R01e新提交5c8e54dc（tree d00c5232）独立库CI：source38162912143 attempt1成功，video685+3既有mac Linux跳过/lab298/两包strict0，utility12+6；query38162912123实际Java31tasks BUILD SUCCESS及host34assertions，Darwin38162912121九项成功。OHOS38162912149 unsigned成功，但实际checkout为PR merge e643b03b5499bccad15833fdfc9d8f1141d67b21（5c8e并入d7619227），SOURCE_COMMIT/provenance一致，不能称纯5c8e HAP验证；artifact11710608458未下载/无设备验收。general四live仅快照。证据/tmp/mk-routing-r01e-ci-20261012/summary.json，未做新App联合验证。Android/Pink14接线文件现已冻结，作者相关114/全Python412/Actionlint通过，真实提取workflow命令空selector exit1无stage/Gradle；独立V2进行中，账本仍空。

General CI窄诊断：旧8b98/87eb两run已terminal cancelled，日志测试持续推进无挂死/timeout证据；当前5c8四test仍live/raw404。本轮ci.yml仅对head_ref/ref_name精确routing/MK-ROUTING-20261011设置cancel-in-progress=false，避免阶段push反复打断长suite；其他分支true。完整actionlint前后均相同3个既有旧action runner错误（checkoutv2一处/softpropsv1两处），表达式无新错误，不能称整workflow lint绿。证据/tmp/mk-routing-general-diagnosis-20261012/summary.json及/tmp/mk-general-ci-baseline-actionlint.log。后续旧action升级仍需检查发布契约。

CI旧action窄修：仅ci.yml checkoutv2→v4一处、softpropsv1→v2两处，独立writer核官方action输入submodules/draft/prerelease/tag_name/files兼容，Lead三行diff/hash复核；if/permissions/发布路径/资产/签名/tests未改。完整actionlint1.7.12与diffcheck通过，文件SHA795561ea0a5362525fd9b0cca7f0c9ba66087d23a92b1b68e43821ccea96c79d。只workflow语法/合同验收，不实际发布/native验收；与CONFIGdirty分开提交。

Android/Pink实际Release接线中央6111864635进行中：一次exact source向量、受审A/JAR与B/manifest-evidence双artifact获取、固定selector与账本、bootstrap/副本/显式routing source gates、实际localJAR+arm64Only构建参数、APK后/ABI/sign/parity/finalize。账本仍空，不批准native，缺接受记录必须Gradle前失败不回旧JAR。pending-parity仅中间材料，全部门过才candidate；旧parity对libapp AOT的潜在差异未实测、不删门。生产pin/metadata/签名不放宽，routing不release。

DV0011095原review5483753705/6110373174/6111479264未修，DEVICE继续原配方/native owner/YUV arm/实机单写，CORE为唯一公共集成者。PR5最新5b历史16行已归aeaf，3md逐字/6hash/相对链接核验，两脚本未导入；188/34info/244为旧8bed+a3+JARcd5声称，原manifest日志未随PR入库，AVC EOS不等dvh1/HDR、UX归因未证。DV001与PR5最终归并、真实完整manifest及最新P5/P8.4/true与false/普通Session/HDR/持续性能仍必需，不能结项。

保留LG批准FULL/range1/YUV8、精确设备门及owner/ACK/lease；不重开10bit/lease融合，不以关闭实验替代验证，产品experimental默认false，true主场景并false回归。ST+PQ不是已证YUV presenter，实际carrier/arm仍待DEVICE协作证明。主任务PR保持未merge/close/publish。

HA真实widget超时根因已独立FakeAsync最小复现：fake-zone创建Completer/real-zone等待造成完成微任务滞留；real-zone创建立即成功。仅harness修正交原writer，Switch/Hive/Session实际断言不变，未称修后通过。证据/tmp/mk-ha-zone-repro.dart。Release r1复审8实际反例拒绝/14hash稳定，额外absolute/escaped资源声明语义及真实私有offlinepubget仍核验中。

CONFIG实际库候选已冻结20文件（/tmp/mk-config-library-freeze.json，SHA256 9ebeafd0579815e3cad6b9a5d73a0f068d56491754ea2714a9acd9312b402a90），作者完整743项与strict0；同配置贯穿planner/Session/report、require实际源codec/MIME/HWkind、queued stop及分阶段清理重试已有实现，独立V2正在审查，未提交、未声称闭环验收。App实际HA widget已通过且检查hwdec=no/fulfillment；真实page慢open事务等待与并发非法代次两例通过，最新全Flutter/strict/bundle联测进行中，不沿用此前71项结果。

Android/Pink第二轮V2仍REQUEST_CHANGES：真实offline pubget生成文件/插件链接被误拒绝，转义YAML build资源可绕过哈希且真实bundle包含它。原8注入已拒绝，但不能抵消这两项。第二轮修复由原writer实施，新增持久Dart YAML解析工具与直接测试、精确生成文件/链接契约；已允许独占复用reviewer私有SDK/cache，原证据保留，产品依赖/规则未改。待实际Android与Pink source→pubget→prebuild及真实资源正负例后再V2。

用户再次提醒归并DV001与PR#5，仍明确列为未完成；文档导入不替代原配方修复、脚本审查、最新适用native产物与实机验收。


### CONFIG模型提交时状态快照（历史）


本CONFIG模型检查点以库8b98+App08acc为代码基线，新增不可变requested/override/effective配置与来源/序列化、纯App设置适配及库一行public export。V1独立35库+22App+4额外反例/两target strict通过，5文件与实际HdrMode/HwDecType哈希一致；隔离纯模型测试最初assets失败保留，最终no-test-assets通过，不是App全量。experimental默认false，explicit auto/reset及按库→App→open完整覆盖；require不被实验/失败策略暗弱化。默认MC组合prefer hardware，disableHA require software；旧原串、copy/direct未完整迁移及未知mode诊断保留。事实模型尚未接DASH/NetworkSource/planner/Session/report，不能标配置闭环完成，后续caller必须处理未知mode诊断。handoff见库docs/plans/core-config-model-handoff-20261012.json。R01e与Release接线其他dirty改动不进入本模型切片。

最新完整已验源码向量只为App08accb63df8c4cab62d00946fb2159dd3781e0ee+库8b98c67a293876bd4af3f36ff245968ca848b41e：source38160661703 attempt1 SUCCESS，四平台真实bootstrap各211/strict零问题/bundle/finalize、Python359/Chrome1/Web；8份source/Build内实际bootstrapreceipt前后向量/10routing+261roots/102toolsroots及2662hash一致，无SKIP。Build38160661882整体FAIL但源码矩阵全成功，6Release既有前置失败，不native验收。库628video+3原mac Linux跳过/lab298与strict/query/Darwin9/OHOSunsigned成功；general四平台test仍live/运行中log API404，未重跑取消跳过。Windows已真实成功，但旧PNG因果未单独证明。证据/tmp/mk-routing-ci05-20261012/summary.json；这些结果不重标本模型提交。


当前已推送库HEAD9152154473901b750553be96dbc2137c927b2f5d；App f179e21a7c20f9f167232c060f90f32d702c19bd；FFmpeg9aba43cf；DEVICE构建DV0011095a43。库source38158342447：604video通过/3既有macOS例Linux跳过、lab298、两包strict；query/Darwin/OHOS成功，general38158342443最后四项test仍运行，不推定通过。App f179+915两run source38159246222与Build38159246432均失败：Android/Linux/macOS真实bootstrap通过（strict零问题、各211Flutter、bundle、真实SDK/package补丁、10routing+261全部roots、源码前后/final一致）；Android另Chrome/Web通过，两run Python本轮各309。Windows因source SDK tracked PNG修改拒绝，绝对路径261字符只是原因嫌疑，实际工作文件hash/diff尚缺；不忽略/重置。Build另6个既有Release前置失败，非native构建通过。证据/tmp/mk-routing-ci04-20261012/summary.json，旧f750向量成功不重标f179。

CORE-F01/R01a/R01b/R01c已实现并分别验证；R01c已推送91521544。R01b完整输出请求契约不证明实际YUV carrier。R01d普通decoder采样已修复两项critical阻断并完成独立复审：缺失track codec等待/拒绝，consumer不跳过MIME证据；ordinary→native内部重开成功清空旧普通观察。11文件255项与全包strict通过，两门删除负例实际红灯后恢复。当前检查点待提交，源码/hash/日志见docs/plans/core-r01d-handoff-20261012.json；此前187/214绿灯未覆盖问题的历史保留。review预算不包含open admission，Dart timeout不能抢占同步native FFI。生产普通open的entry/epoch在Player锁内捕获，FILE_LOADED在锁外等待；当前scalar decoder/frame/MIME/config A/B一致性与代次检查、embed拒CPU已接通，失败不虚构排除依赖。完整copy/software catalog与auto/prefer/require有效配置闭环仍开放。

CI03 34 info已清零；DEVICE新增旧8bed+a3向量的34info不覆盖当前CORE零问题。CI04 Windows窄修按中央6111697645推进：短私有路径、首次checkout/SDK前长路径支持、拒绝前完整差异证据；保持来源门。App native输入gate四新文件待独立critical，接受账本空，未授权DV001；workflow/native候选尚未接线验收。experimental产品默认false，true主测/false回归保留。

用户明确要求归并DV001与PR#5；此前86c186f三Markdown历史切片已归并，现续接5b27961137a3b03e687dddbeb05a0320fcf6c60c唯一device-results追加16行。逐文件来源/原文与导入hash保留；两个配方脚本仍未导入。DEVICE6111648066与新增文档一致，但188Flutter/34info/244Python的本机原日志未随PR入库，按DEVICE声称保留。AVC EOS02:51不等于dvh1/HDR验收；dvh1菜单后e2e仍未执行，UX归因未验证。DV0011095原审查未修，DEVICE继续原PR所有权，不能标两PR已完成。

DEVICE6111344927的原LG候选实体呈现证据保留，DV002 passed_for_vector，黑位/过曝既有项仍登记。native owner/YUV arm、普通无define Session、完整来源manifest和最新整合P5/P8.4/true与false复测仍必需。CORE不另写配方，不改LG FULL/range1或owner/ACK/lease。主PR未合并/发布。


### DV/CI状态校正前快照（历史）

当前库HEAD12966e7ac78983807199e0a179e84ad763a547a7；App da28171292931d32a1f4954f495ab5b7c29852a6；FFmpeg9aba43cf；DEVICE构建DV0011095a43。最新已验源码组合为库12966+App c51fd0973：库source38156773328 video591通过/3原mac跳过、lab298、strict通过；App source38156848733 strict零问题、211Flutter/1Chrome/268Python、Web/bundle/10包来源及freshness通过。Darwin/query/OHOS成功，general38156773301仍in_progress，不推定整套CI完成。证据/tmp/mk-routing-new-ci-20261012/summary.json。App da281是后续URI窄修，不能重标旧运行。

CORE-F01/R01a/R01b已实现并验证。R01b内部输出请求contract/复用身份与publish失败清理已推送12966；它不关闭realizer中ST+PQ推定YUV的实际carrier缺口。R01c首阶段已实现并critical通过：仅实际绑定等待typed timeout，普通配置/open/review超时停止清理；持续二次hwdec/route mismatch拒绝accept，coordinator二次reopen拒绝。合法预算SDR兜底及已准入第二HDR均保留；worker228+1，独立critical231及全包strict零问题。原4行为红灯保留，true先失败的baseline不虚称false红；route-only仅最终覆盖。cleanup债务stop/reset回归保留。源码hash/边界见docs/plans/core-r01c-handoff-20261012.json，后续新CI待。完整实际decoder/采样身份预算、copy/software catalog、auto/prefer/require有效配置闭环仍开放。

CI03 34 info已清零；Release38156848910 FAILURE：cache/兄弟源码/旧锁/空tag前置失败，非native编译验收。App bootstrap三新文件正在按V1修改，mock通过不算真实3OS；产品experimental默认false保留，验证true主场景和false。

用户明确要求归并DV001与PR#5；中央6111454734/PR5 6111454975登记。PR5最新86c186f0的三Markdown历史证据已导入并通过critical原文/6哈希/5相对链接核对，新增README Current State与original/import SHA256 manifest；原正文逐字保留，两shell脚本未导入。原input-vector与device-results混记多轮，不拼成单一验收向量。DV0011095原review5483753705未修，配方仍DEVICE所有；不能标两PR已完成。

DEVICE6111344927证明原LG候选实体屏幕颜色亮度基本正常，DV002呈现项passed_for_vector；黑位/过曝既有项仍登记。native owner/YUV arm、普通无define Session、完整来源manifest和最新整合P5/P8.4复测仍必需。CORE不另写配方，不改已批准LG FULL/range1或owner/ACK/lease。主PR未合并/发布。


- 2026-10-11：全文读取takeover/v3/中央App台账/F01/CI02/最终评论及DEVICE最新认领；中央登记接手与文件范围6110756605、续审6110762843。CORE-R01a已派发worker，DEVICE配方保持其所有权。

### 2026-10-12 前序检查点（历史）

2026-10-12：库最新已推送bd9b9f852949af8980faaad337064a0830c405da的R01a终态中央6110898494：573video+3原macOS专用Linux跳过、298lab及两包严格分析通过，query/实际插件Java、Darwin宿主及OHOS unsigned HAP各成功，完整native/设备验收未完成。App最新1965ba0e6c50316f1a64f6830bb0877d5f84606e（CI03）已推送回读，本地严格分析No issues、211Flutter、bundle、Chrome DOM与实际main_web release构建通过并独立复核；中央6111208521。远端source run38155973408尚在执行，已完成Python job114518915972实际263项通过，artifact11708632336；不虚称远端App整体通过。

CORE-R01b已实现内部创建请求契约统一，范围新hdr_output_contract、Slot/backend.prepareOutput/Session._createController及直接测试，现有Slot类型导出配套contract一行导出。完整vo/topology/requestedHwdec/GPU/EGL/Surface/offscreen身份用于复用，不推导已观察YUV arm。旧初始未知身份重建、失败且清理失败的输出不能偶然ready后复用，publish异常纳入原失败清理。旧测试配置共享SDK边界已发现，私有pubget重解析成功且无tracked lock变化；最终64目标私有SDK测试/全库strict通过，独立critical复审78项/全库strict通过。新增发布失败两例修复前红灯保留，真实carrier夹具已改surfacetexture。日志/tmp/mk-r01b-{final-tests,final-analyze,publication-baseline,review-final-tests,review-final-analyze}.log。检查点及后续CI见docs/plans/core-r01b-handoff-20261012.json；不能据此声称native呈现、实际decoder或完整R01完成。

App1965ba0e+库bd9b9f85 source run38155973408 attempt1已SUCCESS，实际strict零问题、211Flutter/1Chrome/263Python、Web/bundle与10包前后源码绑定/两仓freshness通过，中央终态6111284247。source artifact11709080173/Python11708632336已下载按ID核验。Release Build38155973649整体FAIL，所有平台失败在native/ABI/签名前（cache/兄弟source/旧锁/空tag），其源码子作业通过不表示Release通过。此终态只证明旧bd9向量，不改标R01b新库。

已读取DEVICE最新中央6111018306/6111060791并回应6111090195：P8.4路线/数据空间仅passed_for_vector，NV12/HWC合成证据不等于实体呈现，截图黑不定性生产渲染失败；保留批准FULL shader+range1。native process-global arm与advisory owner由DEVICE登记修复，公共Dart仍CORE唯一集成；旧DV001构建审查不因DV002更正关闭。真实decoder/presenter复核、可执行独立软件catalog、配置闭环、ReleaseCI/native/设备验收仍开放，产品experimental默认false。

### 接手及R01a首次检查点（历史溯源）

CORE继任已登记中央PR4 comment6110756605。唯一三个routing/MK-ROUTING-20261011分支及主草稿PR继续；DEVICE负责原native构建/实机，不新开工作线。干净worktree接续，原checkout dirty均保留。

权威方案为v3，接手入口为docs/plans/media-kit-routing-core-takeover-20261011.md。CORE-F01模型/Session/plan/report和App报告回归均已实现并完成宿主验证，终态6110447335/6110417510只证明库6e7570fc+App569138fa：571video、3原macOS专用Linux跳过、298lab、192App Flutter、同App SHA此前244Python、bundle/来源/新鲜度通过；分析34info，整体未全绿。原planned/pending已归并，不重新实现。

CORE-R01a仅认领hdr_route依赖标签、realizer::_baseLayerConvert、Session::_hwdecDependency及测试。SurfaceTexture请求路径不等于YUV presenter，mismatch不声称decoder/importer根因；输出slot/backend/GPU契约/软件catalog仍后续开放。不改LG像素、owner/ACK/lease/nativeDV/源事实或App默认实验门。

DEVICE DV001仍1095a43，review5483753705/comment6110373174没有新修复。续审6110762843：nm失败误放行、仅QueueFamilyProperties2漏检、正式bundle传播/staging/成员来源未闭环；PR5 cbcc6bb8档案复制符号缺陷，输入表与结果SHA不一致、完整APK/patch/链接来源不足、LYA帧推进缺证。本机JAR三成员及显式NDK读取支持该样本no-op，不证明配方或最新F01/HDR验收。保持未集成，DEVICE在原PR修。

R01a实现已完成：最终hwdec独立SurfaceTexture依赖与Session排除，双门成功copy及二次失败有界测试；50关联用例通过，严格分析无问题，V1独立审核无阻塞，独立92关联用例通过。源码CI/App最新组合未验收，记录见docs/plans/core-r01a-handoff-20261011.json。

下一步：独立审核后及时commit/push/readback、当前源码CI；随后输出身份/decoder复核及可执行独立替代，真实选项闭环、34info和Release CI。构建开始固定最新适用输入，期间不pull；旧向量不重标新SHA。

### 2026-10-12 Current State 校正前快照（历史，不作当前结论）

旧状态快照

唯一集成分支 routing/MK-ROUTING-20261011。远端当前库d91639401862d84c68406aae3b2029400a4cfbd6、App 1970d440b5b9d9ffc001866064581e4005b26b30、FFmpeg9aba43cfbee182ade060cdccbe15340a0fbe3e83；DV0011095a43、PR5 5b279611未见新修复回交。中央认领6113083125。主PR均未合并/关闭/发布；root唯一公共集成者，DEVICE继续原recipe/native/实机责任，原checkout未知dirty保护。

已完成F01/query/DASH/未知DV/FFmpeg e8df200c、R01解码导入呈现依赖/输出资源契约/实际decoder复核/有限独立copy软件路线、auto/prefer/require有效配置贯穿App选源/planner/Session/report以及请求代次和清理债务；不按旧planned重做。LG配置claim回归已修并独立V2及当前源码CI验证。34info已清零、当前strict0；默认experimental=false，主验证true并回归false；LG FULL/range1/YUV8/精确设备/ownerACKlease保持，不重开10bit/lease融合。

当前完整源码验收仅e31a+d916：App source38169989794 SUCCESS、Build38169989974 failure但其源码矩阵也完整SUCCESS，两套四平台各268/strict0/bundle/finalize；Python本轮实际451两次（177.586/182.022s）、各7真实parser/kernel/identity。库38169536268 video772+3原mac Linux跳过/lab298/strict0，query34+实际Java/Darwin9；OHOS实际PRmerge eaee10dd单独unsigned范围，不是纯d916或实机。证据docs/plans/core-source-prelude-ci-checkpoint-20261012.json含21artifactIDs/hash；完整822文件索引保留本机。general只有pending快照，不推定通过。旧6c4+751/其余旧向量证据各自保留不重标。

Linux/Windows A四文件已第二修正Critical通过并在e31a提交：完整captured vector允许caller PR/dispatch，直接routing/缺向量拒绝，作业名中性。43contracts/actionlint/20实际条件及pwsh失败传播验证。Hosted两Release真实prepare/verify/finalize各57steps0/fresh-source-only后SOURCE_PREPARED_NATIVE_BLOCKED（11713952189/11714201466），旧下载全部skip；原始job日志复核：verify步骤内实际bundle命令成功，未单独归档bundle digest；独立源码矩阵另有bundle证据。不是native或整个平台Release通过。旧两轮REQUEST_CHANGES保留在core-linux-windows-source-prelude JSON。

Android/Pink来源/YAML/生成物/plugin精确契约与双artifact接受门已提交保留；当前ledger/selector空，最新两Release实际preAPI/prestaging/Gradle拒绝，不借旧JAR。旧准确6c4+751已真实clean SDK/Android/Pink prepare/offline lockedpubget/prebuild/lock/finalize成功，各1888inputs/31pubGenerated/3buildGenerated/86links，bootstrap6b261eff；只source前置，无native或variant postbuild验收。原SDK36dirty、失效cache symlink、driver参数错误均保留。此历史向量证据core-source-prepare-checkpoint不改标e31a。

iOS六文件实现首审REQUEST_CHANGES：Android/无platform/wrongscope回执绕过；首修19variant+31bootstrap及原9拒绝通过，但Critical仍REQUEST_CHANGES：实际Android SDK patch重标两个ios标签仍finalized，当前原writer第2轮加三个实际SDK文件的受审iOS patch reverse-check语义、成功补丁步骤来源，并修deepcopy列表引用，待重冻复审。都是真实临时Git+模拟pubget，实际iOS bootstrap/pubget/hosted/Xcode尚未验；未审源码在工作区，不写共享workflow。证据core-ios-source-variant-review JSON保留原失败。

Linux B消费者九文件已冻结（作者库5/App verifier7/acquirer3合成测试通过），独立Critical正在核验真实CLI/CMake参数链、非空synthetic批准和consumerSourceClosure；证据core-linux-native-consumer-review JSON，生产ledger仍空，未批准真实native。不执行伪App helper自授权，不套Android3成员规则、不改DEVICE producer。pr5_matrix_integration单写库tool/matrix-build.sh/routing_matrix.py/tests/README，将公共矩阵归唯一入口，真实fixture内容/当前source/受审native/每APK ABI签名来源与失败传播，已冻结四文件（作者12模拟tests），native_release_review独立V2进行中；不新增弱化/打包配方。root拥有汇总JSON/TASKS/context/Git，其他dirty不混提交。

DV001/PR5必须完整归并：三历史MD及16行已e162/aeaf归入；两脚本仍未完成。assemble-jar-arm64重复DV001且留nm读取失败/单目标问题，由DEVICE归原canonical bundler；matrix-device-build公共功能归现tool/matrix-build.sh。路径/blob/hash与去向见core-pr5-script-inventory JSON，不是脚本批准或整项完成。DV001各符号/ABI/部分写/失败传播/clean staging/最终成员链接补丁manifest仍待原PR修复。最新受审native、八包实际构建、P5/P84 truefalse/普通Session/owner实际carrier/可见HDR/持续性能仍缺同向量验证；旧AVC EOS/模型SDR不能替代。

下一阶段：复审iOS第二修正、V2审核已冻结Linux B与PR5矩阵，再由root准确stage/中文commit/push/readback、最新组合复测。Linux真实producer→consumer→bundle、iOS workflow/native消费者、Windows native/其他Release仍继续原DEVICE协作，不因源码绿或空ledger正确拒绝结项。汇总JSON校正随下一真实源码checkpoint提交，不纯记录push反复取消CI。

2026-10-12继续检查：Linux B冻结九文件已交linux_native_review V2，postbuild CLI/插件名疑点正在独立复现，未提交。PR5实际Lab _hdrRoutingPolicy中HDR_GATE_OPEN=true令allowExperimental=true、HDR_POLICY_EXPERIMENTAL=false保持默认排序；矩阵作者新增逐行allowExperimental字段与八行模拟顺序，尚未冻结/复审，不算八APK。iOS独立clean工具链准备首次agent-slot不足已记录，原Linux作者完成后重派ios_clean_toolchain_prepare成功；只clone验证SDK/cache输入，不运行未审iOS脚本。磁盘1.3GiB，不清理原资料，旧Android-patched SDK/cache不可改标签当iOS。

PR5矩阵四文件准确冻结记录core-pr5-matrix-review-20261012.json（库d916），12项模拟tests不代表真实八APK；与Linux B V2并行，均未审通过或提交。Linux独立复现已发现postbuild参数与插件名缺陷，另RPATH允许额外绝对路径，审核仍收尾。

Linux B首审终态REQUEST_CHANGES：38独立probe/15已有tests与最小CMake真实configure，准确五P1（postbuild双层参数、实际插件名、绝对RPATH、不可达bundle布局、App linux/与shared gate闭包遗漏）；原writer第1修正已授权。原9hash/HEAD冻结一致，报告1f9c4b84保留，未声称native批准/编译。

PR5首审终态REQUEST_CHANGES：正常lab自身package根、Flutter完整APK成员与非法build --build-dir阻断，成功receipt仅内存未落盘；P5明确DV事实应独立于缺失裸BT2020 VUI。首轮四hash不变，12原tests仍过不能抵实际CLI失败；原作者第1修正已授权，未提交。iOS新clean SDK输入r1精确源tag3.47.2/官方origin与describe已补并全量hash复验，证据1a542619；只准备输入，不是iOS bootstrap或构建通过，旧Android-patched cache保持。

中央最新review登记6113395912：Linux B与PR5首审真实失败/修正范围、SDK输入与DEVICE同原PR回交边界已发布；不改标旧CI、不启动第二配方。


iOS六已审source+root记录已精确提交push/readback App1970d440b（six committed blobs逐hash=V2），库仍d916；未混Linux B/PR5未审source。source38172589162 pending、Build38172589627 queued为真实新1970，重复source38172585650已cancelled，不拿旧e31全绿改标。ios_clean_toolchain_prepare正在新clean两个checkout/私有SDK/p空运行真实当前iOS前置，期间不push新向量；Linux B第1修正新冻结已交V2，App新HEAD为独立iOS提交，九ownedbytes未被此commit触碰。

原e31a+d916前置bundle更正已按两个原始job日志+成功step API核实（Linux114560490516/Windows114560490505）：实际命令及nonzero throw guard完整执行后进入finalize；不是独立named bundle step，也非单独归档产品hash。原摘要ac15事实错误保存并附更正，不重标1970/native。

Linux B第1修正V2仍REQUEST_CHANGES：18原tests/49独立probe及实际generated postbuildCLI，旧4问题关闭于synthetic scope；剩余allDSO ABI门被删除回归和requesterRPATH/RUNPATH非传递缺口。原writer第2/最后修正授权，必须恢复原ABI及逐请求者可达性门，不删失败断言/制造绿；新freeze再V2，真实native仍未批准。报告118ff41e保留。

实际1970+d916 iOS bootstrap/sourceverify/finalize已exit0/fresh-source-only，before/after/final精确向量一致，真实SDK三文件语义和两patch阶段身份在receipt；variant启动前因仅约158MiB(<256MiB reserve)准确停止，尚未创建或验证。完整raw e8f4d8d1保留本机，项目compact checkpoint附源hash/step结果；只source前置，不是Xcode/native/Release。只读同字节cache统计正进行，不清理材料/复用Androidpatch。
