# MK-ROUTING-20261011：CORE 继任 agent 接手指令

版本：1。任务日期：2026-10-11。本文由原 CORE 根据用户要求发布，供另一个 agent 接替 CORE，而不是新增 DEVICE 工作线。

**接手性质：继续已开发的同一任务，承接公共实现、CI、代码审查和唯一集成者职责。已在工作的 DEVICE agent 继续负责 native 构建和实机验证。原 CORE 本轮仅做交接，不再新增生产代码。继任者尚未在本文发布时登记接手，不能把交接文件当成它已执行任务的证据。**

## 1. 先执行这六步，不要先写代码

1. 读取 Goodwu/media-kit PR#4 的最新正文、最新评论及 DEVICE 修复 PR；读取本文。中央协作入口始终是 PR#4。
2. 读取整体执行方案 v3、中央和 App 台账、CORE-F01/CORE-CI02 增量记录以及下列最终结果评论。台账的旧 pending/planned 不是重新开发依据。
3. 核对各仓真实 remote、当前任务分支 HEAD、PR base、已有本地工作树和 dirty 状态。保护未提交修改；不得用 reset --hard、git clean 或重新从旧 main 建分支来消除差异。
4. 在 media-kit PR#4 发布 `[CORE-SUCCESSOR]` 接手登记，写明接替原 CORE、当前源码组合、工具能力、第一工作项及拟修改文件/函数。通知 DEVICE 唯一集成者已更换，不重开它的任务。
5. 审查 DEVICE 的最新进展和认领，接续 DV001 已有审查意见。没有新版本时让 DEVICE 继续原 PR，不另写相同构建修复。确认共享文件范围后，从第7节第一个未完成 CORE 项开始。
6. 第一个可恢复实现阶段即 commit/push；独立测试后记录真实结果，保持已有任务分支和 PR。不要完成整批才推送，也不要把未验证代码标为通过。

用户已授权开发、提交、推送和环境允许范围内测试；不必重新询问是否开始总任务。新增破坏性操作、生产发布或设备刷机/清数据等不在该授权内。

## 2. 必读资料与过期状态处理

所有路径都必须从对应当前任务分支读取，而非默认分支或旧只读工作区。

### media-kit
- `docs/plans/media-kit-routing-implementation-20261011.md`：唯一整体方案 v3；不是早期 RFC v1 的全栈重写方案。
- `docs/plans/media-kit-routing-handoff-20261011.json`：schema3 中央历史台账。
- `docs/plans/core-f01-handoff-20261011.json`：已实现原始源证据模型与 Session 接线。
- `docs/plans/media-kit-routing-parallel-device-handoff-20261011.md`：CORE/DEVICE 分工、分支、认领、候选和设备验收协议。
- PR#4 最终结果 **comment6110447335**；早一阶段 CORE-CI02 **comment6109490925**。

### PiliPlusX
- `docs/plans/media-kit-routing-app-handoff-20261011.json`。
- `docs/plans/core-ci02-handoff-20261011.json`。
- `docs/plans/core-f01-app-handoff-20261011.json`。
- PR#1 最终结果 **comment6110417510**；CORE-CI02 **comment6109486294**。

### native / DEVICE
- Goodwu/FFmpeg PR#1 和 `doc/media-kit-routing-handoff-20261011.md`，以最新实现及结果为准。
- Goodwu/libmpv-android-video-build-dv-experiment PR#1（DV001）：读实际 diff、review5483753705、comment6110373174 及后续回复。
- media-kit PR#4 的 DEVICE 登记6109258398、整改6109723491、阶段报告6110194338；CORE 范围/证据回复6109294215、6109798715、6110286711。
- LG 历史：`archives/conversations/lg-h870ds-hdr-demo-20261004.md`、`docs/plans/lg-p84-hdr-followup-plan-20261009.md`。历史验收只在对应向量/条件范围有效。

**已知过期字段的确定解释：**
- 中央 schema3 的 `B1b-original-decoded-fact-lifetime=planned` 已被 CORE-F01 实现和终态取代；不得重做。
- 旧 App/中央台账的62条分析信息已降为34；34仍未解决，不能写成已清零。
- CORE-F01 增量 JSON 的 pending validation 已被上述6110447335/6110417510的终态取代。
- 旧“FFmpeg只复现未修”“query尚未迁移”“App分支尚未创建”等早期记录都已失效。

下一次真实实现 checkpoint 将这些已完成状态归并回中央/App汇总JSON，保留旧证据引用。不要删除历史失败，也不要仅凭更新时间覆盖另一个源码组合的结果。实际代码与精确运行证据优先于旧摘要；最新认领决定当前负责人。

## 3. 唯一开发链与现场核对基线

下表是**发布本文前**重新查询远端得到的状态。本文是新文档提交，会使 media-kit HEAD 前进；这些 SHA 只用于溯源，不是以后构建旧代码的钉定。继任必须再次取最新 HEAD。

| 仓库 | 分支 | PR / base | 交接前观察到的 HEAD |
| --- | --- | --- | --- |
| Goodwu/media-kit | routing/MK-ROUTING-20261011 | #4 / main | 6e7570fcdaadeb66223a7327860000bb945daeb4 |
| Goodwu/PiliPlusX | routing/MK-ROUTING-20261011 | #1 / fix/darwin-video-output-rebuild-barrier | 569138fa8d55eb2686578fc834c19aba8093c411 |
| Goodwu/FFmpeg | routing/MK-ROUTING-20261011 | #1 / lg-p84-d1-vui-fix-20261010 | 9aba43cfbee182ade060cdccbe15340a0fbe3e83 |
| Goodwu/libmpv-android-video-build-dv-experiment | device/MK-ROUTING-20261011/DV001 | #1 / feature/android-dv-build | 1095a43acb4d0973b8bca59c5da4e300657bdb29 |

这四个 PR 在本次核对时均 open、draft、未合并。App以前的整合用PR#2已经合入任务分支，不是主任务PR#1已经合并。不要重建主PR、改错base或再合入同一修复。

CORE继任直接继续前三个既有集成分支；它不是另一个device分支的负责人。DEVICE增量修复分支只回流到已登记目标，由CORE审查/集成。构建仓是已明确登记的例外，DV001 base为feature/android-dv-build，不要机械改成它不存在的routing分支。

本任务 CORE 尚未修改 mpv/libplacebo 生产源码。DEVICE已报告使用 mpv产品线c11426b67a、libplacebo产品线ea700489、helper b768ce102；这是报告输入，不是授权以后忽略更新。其真实remote和产品分支由DEVICE的manifest核对，不能猜上游默认分支就是产品输入。

## 4. 已完成清单：禁止重新实现

| 成果 | 实现锚点 | 当前范围 |
| --- | --- | --- |
| P5/P8.4 准入与未知EL | media-kit d18de275、f0bba6ff | profile32/256分开，明确EL=false；删除DV显示能力授权HLG直出的全局例外 |
| 目标和源规格能力查询 | 63971455、5638f9b5、861b9ab2 | VideoRouteCapabilities.query(target:, sources:)；无Player，Android按目标和完整源规格查询；库/Session/lab已迁移，旧Dart HdrCapabilities.query/queryWith已删除 |
| App真实选源过滤 | PiliPlusX384b10ae、4f7fcd66 | DASH逐rendition的codec/coded size/fps等匹配，先过滤后偏好；菜单/切换/NetworkSource交接；没有全局过期快照回退 |
| 已有Android7修复整合 | media-kit8b80f452、Appd0926b31 | 正常合入已有成果，保留历史，不重复实现 |
| 失败感知SDR兜底 | 98a349f7、e4f7af3c | 兜底不忘记失败依赖，无独立正确路径则阻止；不是完整软件替代路径catalog已实现 |
| 未知DV源分类 | 2a5d87f0、cb14f853、8de0de00 | dvUnknown/未知颜色语义明确保留；实验、自定义策略、SDR兜底都不能绕过；29测试和12类矩阵 |
| App未知DV过滤与报告 | 8f82d294、b6f63ec5 | 不凭画质编号或坏profile猜P5/P84/EL；allowUnknown解码能力不授权未知颜色；保留已声明B站P8的provider hint边界 |
| FFmpeg实际选择修复 | e8df200c、9aba43cf | P8 lookup和configure同profile256；空/缺失DV能力不授权；已有宿主与Android目标编译，不能再写一遍 |
| App构建基础接入 | 223031bb、2c4001fb、e80a52f0、c6c72369、ea07f530 | 可移植依赖、10包来源核对、SDK补丁衔接、Apple必填ref；旧Build的HDR作业复用当前源码验证，其他发布job还未全迁移 |
| CORE-CI02 | App5370a187、746ef93e、504a3e98、8bed4a4f | 2个普通UI文件/测试，62→34info，10新用例；Get.reset同步契约已纠正 |
| **CORE-F01原始源证据生命周期** | **media-kit a3cdbda2、867ffd28、6e7570fc；App569138fa** | **21模型+9Session+4App回归，全部已验证；真实Session/plan/report已接线，不是模型空壳** |
| 其他已交付兼容/验证 | media-kit445a2add、1c134790、c2afeb990等 | OHOS条件导出、JS/Wasm/平台测试修正；JAR身份解析/哈希门已修，不能删除 |

所有这些实现均已远端持久化。测试失败只改变验证状态，不使已推送实现回到planned；继任首先检查提交和代码是否存在，不从头复制本表功能。

### CORE-F01特别需要保留的事实契约

`HdrSourceFacts` 按一次逻辑open保存 source、initialHint、逐字段origin和冲突，同时独立保存最新videoParams/帧侧数据。字段缺失不能抹掉既有源语义；track纠正hint与两个明确track事实冲突是不同情况。hint保留不等于已验证。nativeDV证据验证在合并源事实之前执行，其处理后的gamma不能反推原始DV compatibility。

内部失败/复核、能力或配置重开保留证据；新的公开open即使同URI也重置；旧generation不能发布。冲突阻止路线并保留证据。原Surface/owner/ACK/nativeDV安全门没有改动。

实现入口：`media_kit_video/lib/src/hdr/hdr_source_facts.dart`、`hdr_open_plan.dart`、`hdr_output_report.dart`、`hdr_video_session.dart`以及对应测试。原`HdrSourceClassifier`独立API仍是无状态；Session采用每open证据解析器。**没有新增raw-bitstream探针、on_preloaded事务、live轨道切换支持或全新native协议。** 不要把这一明确边界称为F01“尚未开发”，也不要把更强原始码流观测宣称已完成。

## 5. 最新已执行验证：只适用于记录的源码组合

库6e7570fc + App569138fa是最新已核对的CORE联合验证向量；本文文档提交本身没有重新执行这些测试。

| 验证 | 真实结果 / 证据 |
| --- | --- |
| media-kit源码CI | 38149366499 success |
| media_kit_video | 571通过；3项原有macOS专用Linux跳过；analyze clean |
| media_kit_hdr_lab | 298通过；analyze clean |
| query/实际Android插件Java | 38149366400 success |
| Darwin viewport / OHOS | 38149366478 / 38149366445 success |
| 一般平台CI | 38149366528在本文写入前再次查询仍in_progress；不是全绿 |
| App源码CI | 38146940852的第二次App job114499858358；App569138fa实际读取库6e7570fc |
| App Flutter | 192通过，包括F01新增4例 |
| App Python | 244通过，同App SHA此前成功作业保留；不是本次复跑了Python |
| App bundle/10包路径/前后新鲜度 | success；bundle不是APK |
| App严格analyze | 34info、0error、0warning，workflow整体failure |
| FFmpeg历史独立CI | 38130404541 success：Clang/GCC各17 selector例+ASan/UBSan，6提取器例；API24/35 arm64有限MediaCodec静态库编译 |

可持久获取的关键归档：
- video artifact11705826654，SHA256 a51d65a5917a94a34c148650e0f71d583ae91b06161a1cdf322a9936d39cc3bc。
- lab artifact11705916517，SHA256 88cb5d6ad706bfa3973ce6025c1b847ec50e6b04e4973eac9f62ad84c172ac45。
- App当前向量 artifact11705617556，SHA256 1af2bb6b49643cb6955c8596461c2fbc3cd1905bd7e99abefc3322ad37be854c。
- App Python artifact11705272968，SHA256 436f70f1320b59993c99fd43b54e7b194ffe1d47277faad2cd6fee13ba072058。

App同run还有同名旧artifact11705292989（旧库867ffd28），**不可只按名字选附件或把重跑前证据标成新组合**。按artifact ID、run attempt、source.txt、实际resolution JSON和哈希核对。下载链接有时效；保存稳定ID、哈希和过期时间，必要证据及时归档，不依赖本聊天临时路径。

已知中间错误：CORE曾误把Get.reset当Future，已按真实依赖的void同步实现修正；F01测试漏import且第一次误导入legacy policy，最终6e7570fc从实际hdr_route_planner导入。失败记录保留，不删测试，不再重复错误修法。

## 6. DEVICE仍在工作：继任不能抢占它的范围

DEVICE负责完整native源码重建、实际JAR/APK和设备验证、由证据支持的设备/native/构建修复。CORE负责公共逻辑、宿主CI、App通用接入、审查和单点集成。双方都可能需要Dart，不能只按语言划分；同一缺陷/共享函数同时只能有一个实现负责人。

### 目前的设备阶段报告，不是最终验收

DEVICE comment6110194338报告：FFmpeg9aba43cf + mpvc11426b67a + libplaceboea700489及保留patch + helperb768ce102从源码构建；JAR SHA256 cd5fe26befeb6e9f96627692f5883abe860381853bac997f45806139c9851622。

App输入为8bed4a4f + 库a3cdbda2（仅模型阶段），有experimental=false与true两包；true包使用工作树测试改动，必须补齐该改动及完整哈希/参数以可复现。SDR观察覆盖LG、LYA、marble、Mi Note3；LYA第二帧证据缺失，帧推进子项未验证。**这不是867ffd28后Session接线的设备验收，也不是HDR矩阵完成。** 完整manifest/脱敏日志/链接来源当时主要在本机路径，CORE已要求持久上传；继任须核对是否随后落实。

### DV001审查未闭环：先接续审查，不重写配方

构建PR#1@1095a43已收到review5483753705和comment6110373174。交接前HEAD仍为1095a43，不能先宣称问题已修。

需要DEVICE在同PR处理并提供回归：
- `nm ... | grep`失败与没有符号不能混同；宿主nm不支持Android ELF或命令失败不能静默放行。
- 只出现`vkGetPhysicalDeviceQueueFamilyProperties2`而未出现`vkGetPhysicalDeviceProperties2`的反例不能漏检；两者均不存在才是可证明no-op。
- 构建/补丁任一步失败必须传播，不能继续链接旧libplacebo.a；时间戳和少量字符串不是完整来源证明。
- 用隔离、干净staging和明确成员清单组成JAR；核对本轮libmpv、源码构建helper及工具链libc++来源，不能用通配符混进历史.so。
- helper及最终打包命令、工具链、输入/patch哈希、实际链接清单、产物和安装包完整哈希应形成可执行/可审查配方，而不是未保存的手工操作。

CORE不要直接修改DEVICE分支。读取新diff/测试后，通过已有PR正常集成；发生跨仓依赖时记录全部向量，合入后还要最新组合回归。不要在问题未修时仅凭“可合并”按钮合入。

### 接管后的协调规则

高冲突文件包括Session、backend、realizer、planner、output slot、App hdr_output/controller、共享CI/SDK补丁。原CORE-F01对source/review相关函数的工作已完成；继任承接公共维护，但编辑前仍读DEVICE最新评论并登记下一范围。不要将旧认领永久当锁，也不能无声夺走新认领。

独立clone/worktree、native build目录和已patch的Flutter SDK/pub cache。若DEVICE需要公共文件，确认函数范围、暂停该范围、修复后归还。聊天不自动互通，双方在开始、共享编辑前、push/集成前和交接前读PR#4。紧急信息可经用户转达，但权威登记留GitHub。

## 7. 从这里继续剩余工作，不另起大型重构

### 第一优先：CORE-R01，实际执行路径/依赖/输出复用/复核

先提出小范围实现和测试，在PR#4登记文件函数，再编码。重点读取现有`hdr_route.dart`、`hdr_strategy_realizer.dart`、`hdr_route_planner.dart`、`hdr_output_slot.dart`、`hdr_player_backend.dart`、`hdr_video_session.dart`。

最小目标：
1. 解码、导入和呈现分开表达；`hwdec=surfacetexture`不等于已选择YUV presenter，实际依赖不再误报mediacodec-copy。
2. 同`vo`但GPU API/输出像素格式/颜色契约/导入资源要求不同，输出不可错误复用；支持原位更新的参数不无谓重建。
3. 复用现有mpv `android-mediacodec-info`及native事实进行复核，不为此预建Dart点名decoder和全新FFmpeg/mpv协议。严格路线和受约束自动选择分开；实际回退只有仍满足完整契约才接受。
4. 失败只排除真正失败的decoder/importer/presenter组合；保留根因、清理错误和总尝试边界。已有98a349f7的失败感知兜底不能撤销。
5. 在当前后端确有支持的前提下增加独立copy/软件替代路径。不要把软件帧交给只能消费MediaCodec帧的embed输出；不能以复用失败链制造“总可播放”。

先覆盖：同策略不同importer失败隔离、同vo的必要重建、真实hwdec与计划不一致、受约束软解回退、旧generation/owner、清理未完成不能再open、实验开关双态、普通SDR不回归。若DEVICE此时占用交界，先做不冲突模型/测试和CI，不抢写。

### 第二优先：高级配置的最小闭环及App对接

实现真实生效的auto/prefer/require。先支持已有路径上的硬解/软解偏好和硬约束、HDR/SDR目标及失败策略，再增量开放GPU/renderer/importer/精度。prefer用于排序；require失败必须解释，不能偷偷硬解或降精度。实验门独立，质量要求独立，设备/颜色/资源安全不能被用户偏好授权。

同一份不可变有效选项必须贯穿App选源过滤、planner、Session与requested/effective/observed报告；App设置持久化和不支持项说明都需测试。不能只增加枚举/设置UI就宣称完成。跨平台统一公共语义，不复制Android决策到App。

### 持续处理：34条分析信息和其他Release CI

先获取当前analyze.log逐项确认。剩余多是复制文本控件的旧API、web入口/包名及跨await BuildContext等；需要菜单/焦点/无障碍/生命周期回归，不批量删分支、改名或ignore清零。

旧Build的HDR验证已迁移，不重做。其他Android/Pink/Windows/Linux作业仍有源码兄弟目录、解析依赖前patch、旧lock/ref问题；iOS的旧OHOS裁剪步骤和macOS的approved-input预检仍有失败。按最新日志定位，在不绕过来源、签名和发布门的前提下迁移。未具备发布凭据时区分可完成的无签名/测试构建与正式发布，不伪造。

### 继续开放但不重复认领

LG普通managed由DEVICE牵头设备侧，CORE提供公共接口；保留精确型号/固件/ABI、YUV8配方、离屏/窗口/vendor字段分层和owner/ACK/lease。其他平台逐个接入能力/约束/报告及已有执行器，未实现项明确unknown/unsupportedControls。

B3除已完成selection外，现有RPU/容器事实协议的端到端交付及剩余事实缺口需要验证。只有具体证据证明缺口才作native定点修复；不要为了“完成第三批”制造跨层重构。更强raw源观察或live轨道变化单独立项，不能顺手引入高风险on_preloaded事务。

## 8. 不可变更的产品与构建要求

- HdrCapabilities.query(player:)是自有接口，已删除查询入口，不恢复兼容壳。保留的HdrCapabilities是值/解析用途。新查询必须无需Player，使用真实显示目标及源规格。
- 源匹配检查同一个decoder能否满足完整coded size/fps/profile/level/位深等；显示HDR、系统支持、持续实时性能和实际呈现是不同证据。
- unknown解码能力与unknown颜色语义不同；P5不能用错误颜色兜底。App已有provider hint不等于通用容器真值。
- 主验证场景experimental=true并回归false。App默认仍false，除非有明确产品变更；记录选源和Session实际policy，不能仅打开lab define。
- 保留已经批准的成熟度提升、LG YUV8/像素契约，不重开延期的10-bit或lease融合，不把LG例外推广全Android。
- 有本地产品源码的组件使用最新适用修改构建，不能仅因旧构建pin方便就排除最新mpv/libplacebo/FFmpeg，也不盲目升级无关上游。
- 每轮开始解析最新候选，保存所有SHA和dirty/patch哈希；构建中不git pull。远端前进时旧向量结果仍可保留，但只算passed_for_vector，最新整合验收需重测。最终短稳定窗口在PR声明，不能用并行为由删除现有新鲜度门。
- 旧JAR/SO/APK只能作为清晰标注的对照，不作为最新候选。缓存仅在全部相关输入可证明一致时复用，绝不沿用未知旧对象。
- 记录实际链接输入、ELF/JAR/APK SHA256、工具链/参数、设备实际加载来源；不只看版本字符串或marker。自有代码最新与编译器遵循当前App契约是两件事。
- 不关闭检查、不删除owner/安全断言、不跳过失败用例制造绿灯。宿主测试、Android静态编译、App bundle、完整native APK、真实设备HDR/性能分别验收。
- 不提交凭据、带鉴权URL、私有片源和未脱敏日志；不清设备数据、刷机、root或改变签名账户状态。

## 9. 工具、执行与及时保存

上一CORE通过GitHub连接提交代码、审查PR、读取/复跑CI和下载归档；连接的Codex工作区曾主要用于只读审查。继任重新探测自己的工具能力，不能假设旧临时环境/SDK/文件还在，也不能把工具名称或旧聊天描述当执行证据。

有shell/Git用独立工作区；没有本地Flutter可以使用现有GitHub源码CI实际运行。新session先发现GitHub工具schema再调用。不要编造命令退出码。没有工具暴露的动作不要宣称已经执行。

通过GitHub Git-data API写多文件时先读最新父提交/树，保留未修改条目，以最新父提交创建commit，非force更新ref，再回读并检查diff。冲突要重新读取、对账，不自动覆盖对方写入。严禁为写源码安装一次性CI helper；早期临时源码写入workflow已退休，不恢复它们。

每个可恢复阶段、长构建前、会话交接前commit/push并回读。失败可以作为草稿检查点保存，但明确failed/not_run。不等全CI绿才保存。结果可先评论持久化，下一真实代码checkpoint归并台账，避免纯记录提交反复取消CI。

每个工作项分别记录implementation、validation、integration：已提交不等于通过，通过某向量不等于最新集成通过；设备报告不等于CORE已复核完整证据。保留原修复历史，正常merge优先；同一补丁不重复cherry-pick+merge。主PR最终合并/发布须满足既有验收门，不能因本次交接自动关闭任务。

## 10. 接手登记模板与第一轮交付

在media-kit PR#4发布：

> [CORE-SUCCESSOR] 我根据用户指令接替原CORE，继续MK-ROUTING-20261011，并接管唯一公共开发/审查/集成职责。已读取core-takeover文档、v3、增量台账与6110447335/6110417510及其后评论。当前三仓HEAD为……，DEVICE当前认领和DV001状态为……。原CORE-F01、CORE-CI02、B2b、B1已完成修复、FFmpeg e8df200c不重做。本轮拟进行CORE-R01的……，只编辑……文件的……函数；native/设备构建配方留DEVICE。实际工具能力为……；采用独立工作区，阶段成果及时push。新的文件重叠请在本线程协调。

第一轮必须产出：接手登记、已归并而非重置的任务状态、当前DEVICE审查闭环或明确阻塞、一个有边界的CORE剩余项实现/测试checkpoint、实际CI/构建结果和下一步。不要只重复贴总体计划，也不要在缺少旧聊天时重做已经提交的成果。

## 11. 机器可读交接摘要

```json
{
  "taskId": "MK-ROUTING-20261011",
  "handoffType": "CORE_REPLACEMENT_NOT_ADDITIONAL_DEVICE",
  "successorAcknowledged": false,
  "outgoingImplementationWorkCompleteForThisSession": true,
  "centralCoordination": "Goodwu/media-kit#4",
  "canonicalBranch": "routing/MK-ROUTING-20261011",
  "preDocumentHeads": {
    "mediaKit": "6e7570fcdaadeb66223a7327860000bb945daeb4",
    "app": "569138fa8d55eb2686578fc834c19aba8093c411",
    "ffmpeg": "9aba43cfbee182ade060cdccbe15340a0fbe3e83",
    "deviceBuild": "1095a43acb4d0973b8bca59c5da4e300657bdb29"
  },
  "completedDoNotReimplement": ["B1-profile-EL", "B2-target-source-query-and-migration", "APP-rendition-filter", "Android7-existing-merges", "B1-failure-aware-fallback", "B1-unknown-DV", "B3-FFmpeg-profile-selection", "CORE-CI02-stage", "CORE-F01-source-evidence-lifetime"],
  "validation": {
    "libraryRun": 38149366499,
    "appRun": 38146940852,
    "appLatestJob": 114499858358,
    "videoPassed": 571,
    "videoExistingLinuxSkips": 3,
    "labPassed": 298,
    "appFlutterPassed": 192,
    "appPythonPassed": 244,
    "appPythonNote": "previous successful job at the same App SHA retained, not newly rerun",
    "appAnalyzeInfos": 34,
    "bundleAndFreshness": "success",
    "allCIgreen": false,
    "nativeDeviceAcceptanceForF01": false,
    "resultsComments": {"mediaKit": 6110447335, "app": 6110417510}
  },
  "deviceOwner": "existing DEVICE agent",
  "deviceBuildPR": "Goodwu/libmpv-android-video-build-dv-experiment#1",
  "deviceOpenReview": 5483753705,
  "nextCoreWork": "register takeover; reconcile ledgers and DEVICE claims; review DV001 responses; implement scoped CORE-R01 importer/output/review regressions, then real route options and App wiring",
  "openCrosscutting": ["App34infos", "remainingReleaseCI", "LGmanaged", "otherPlatformAdapters", "currentNativeProvenanceReview", "latestIntegratedDeviceHDRAndPerformance"],
  "sourceSelectionRule": "latest applicable sources each candidate, SHA records provenance rather than historical pin",
  "publicationScope": "handoff document only; no new production change or test execution claimed"
}
```
