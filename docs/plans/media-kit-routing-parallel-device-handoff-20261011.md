# MK-ROUTING-20261011：并行开发与实机验证交接

版本：1。日期：2026-10-11，Asia/Seoul。

状态：协作方案已发布；DEVICE agent 尚未登记接手，本文没有创建它的工作分支、PR 或设备结果。下一 agent 应先完成环境清点和接手登记，再开始修改。

## 1. 不变的主线，以及本次增加的协作规则

本任务仍只有一个整体开发计划和三个现存集成入口：

| 仓库 | 唯一集成分支 | 主任务 PR |
| --- | --- | --- |
| Goodwu/media-kit | routing/MK-ROUTING-20261011 | #4 |
| Goodwu/PiliPlusX | routing/MK-ROUTING-20261011 | #1 |
| Goodwu/FFmpeg | routing/MK-ROUTING-20261011 | #1 |

主任务 PR 当前均为草稿、未合并。CORE 是当前 ChatGPT 工作线，负责公共逻辑、宿主 CI 和集成；DEVICE 是用户准备启动的、有本地构建和实体设备能力的工作线。

“禁止另开分支重复开发”继续有效，但不等于让并行 agent 同时写同一分支。本次允许登记过的、从当前集成分支派生的增量修复分支。它们必须有明确缺陷编号和回流 PR，不能成为第二套任务主线，更不能从旧 main/旧只读工作区重新实现已完成代码。

CORE 单独负责更新三个集成分支、合入设备修复及维护中央台账。DEVICE 只向自己登记的修复分支推送；它的 PR base 必须是相应仓库的 routing/MK-ROUTING-20261011，不是 main、dev-new 或旧修复分支。主任务 PR 的最终合并/发布仍保留现有验收要求。

## 2. 接手必须阅读的资料

依次读取当前远端分支、主任务 PR 正文与最新评论，再读取下面文件。旧正文中未刷新状态由后续精确结果记录补充，不能仅看某一条 pending 字段重新开发。

- media-kit：docs/plans/media-kit-routing-implementation-20261011.md，当前整体计划 v3。
- media-kit：docs/plans/media-kit-routing-handoff-20261011.json，当前 schema3。
- PiliPlusX：docs/plans/media-kit-routing-app-handoff-20261011.json。
- FFmpeg：doc/media-kit-routing-handoff-20261011.md，以及 FFmpeg PR#1 的实际修复与验证说明。
- 当前最终组合结果：media-kit PR#4 comment6108814703；PiliPlusX PR#1 comment6108817980。
- LG 实现/历史验收：media-kit archives/conversations/lg-h870ds-hdr-demo-20261004.md、docs/plans/lg-p84-hdr-followup-plan-20261009.md。历史设备验收不等于新组合已验收。

本文的分支和协作分工规则补充 v3 计划，不撤销任何颜色正确性、所有权、来源校验或产品验收要求。CORE 后续继续开发前需先检查 DEVICE 的接手、缺陷、文件认领及修复 PR。

## 3. 创建本文前实际核对的基线

这些 SHA 是观察/溯源记录，禁止把它们当作后续永远使用的旧版本钉定。本文本身是新的文档提交，接手时应再次解析最新远端 HEAD。

| 仓库 | 当时的任务 HEAD |
| --- | --- |
| media-kit | 1a8ac0f5f1d5f862ba91577fac7111974131ce75 |
| PiliPlusX | b8303a9c2ce0c07b19bc85528dd1b1d93f72f61a |
| FFmpeg | 9aba43cfbee182ade060cdccbe15340a0fbe3e83 |

已完成而不得重做：target/sourceSpec 能力查询与 Player 查询删除；实际 DASH 候选过滤及 Session 输入交接；P5/P8 profile 与 EL 准入；删除 DV=>HLG 放行；SDR 兜底保留失败依赖；未知 DV 语义分类和 App 过滤；Android7 既有兼容修复整合；FFmpeg e8df200c 的严格原生 DV profile 选择。

已核对的最新库/App组合宿主结果：库541测试通过、3项原有macOS专用测试在Linux跳过，lab298通过，库分析通过；App244 Python、178 Flutter通过，Dart/assets bundle和10包来源及远端新鲜度通过，严格分析仍有62条info、0error、0warning。库run38137189075、App run38137256069。不能将它们称为全CI绿灯或实机验收。

FFmpeg 已有独立 run38130404541：17个生产selector宿主夹具/编译器，Clang/GCC+ASan/UBSan通过；6个提取器测试通过；API24/35 arm64 的有限MediaCodec配置静态库编译通过。这不是完整产品构建，也不证明新修复已经进入App实际加载的libmpv。

## 4. 工作划分：按缺陷与接口划分，而非只按仓库划分

| 工作 | 主责 | 对方如何参与 |
| --- | --- | --- |
| 原始片源/解码后帧事实生命周期、公共planner、失败分类/预算和用户约束模型 | CORE | DEVICE 提供实际日志、最小复现；需要亲自修公共文件时先申请文件认领 |
| App剩余分析信息、通用工作流、依赖来源/新鲜度和报告接口 | CORE | DEVICE 提供本地构建配方、验证结果，不同时重写共享CI |
| 当前源码整条native链在设备环境中的重建：mpv/FFmpeg/libplacebo/必要依赖/helper/JAR/APK、现有本机构建补丁清点 | DEVICE | CORE 接收可移植脚本和manifest后负责云端CI接线；不得两边各造一套互不兼容的构建配方 |
| LG及现代Android设备的configure/start、导入、Surface、HDR画面和生命周期验证 | DEVICE | CORE 做对应可运行的宿主反例及最终集成验证 |
| 被实机证据确认的Java/JNI/C/C++/厂商适配/构建修复 | DEVICE | 修改前登记具体范围；CORE不在同一缺陷上再实现另一版 |
| LG普通managed路径接线 | DEVICE牵头设备侧，CORE负责公共Session接口 | 不预先授权双方同时改Session/realizer；每个交界文件单独认领，先完成基线构建再定最小接线改动 |
| 高级auto/prefer/require及App设置 | CORE | DEVICE 在实现就绪后验证实际执行是否尊重硬约束，不提前复制另一套配置 |
| 中央计划、两仓汇总JSON、最终集成分支与主任务PR状态 | CORE | DEVICE 写缺陷记录、自己PR和独立设备证据；CORE归并结果 |

这不是绝对禁止DEVICE修改Dart。实机缺陷可能出现在任何层；限制是同一问题/同一高冲突文件同一阶段只有一个实现负责人。不能为了避免Dart冲突，把本应在Dart修的错误绕到native里。

设备工作范围先预留给DEVICE，尚未宣称它已接手。若环境核验发现它不能构建/操控设备，应如实退回阻塞并重新分配，不能猜测设备存在即代表拥有控制能力。

### 高冲突文件先认领再改

media-kit 的 hdr_video_session.dart、hdr_player_backend.dart、hdr_strategy_realizer.dart、hdr_route_planner.dart、hdr_output_slot.dart；PiliPlusX 的 lib/plugin/pl_player/hdr_output.dart 和实际播放controller；共享CI、SDK patch脚本及中央汇总JSON。

默认由CORE维护公共逻辑文件。DEVICE需要修它们时，在media-kit PR#4登记文件/函数范围并得到CORE或用户确认；CORE暂停该范围，直到修复合入或明确归还。未获确认可以采集证据和添加独立测试文件，不可推送相互覆盖的实现。CORE同样不得修改DEVICE已认领的native/构建范围。

## 5. 分支、提交与集成

每个设备缺陷分配一次编号，如 MK-ROUTING-20261011-DV001。相同缺陷跨仓使用同一个编号，并登记所有PR的依赖关系。

DEVICE建议使用 device/MK-ROUTING-20261011/DV001 这样的增量分支名。首次创建前先查远端分支、PR及认领记录；存在就续接，不重新建别名。只在确实有改动的仓库创建分支。分支基于刚获取的当前集成分支，推送后立即建立草稿PR。设备修复分支尚未由本文创建。

对mpv/libplacebo或其他尚未登记任务分支的仓库，先读真实remote、dirty状态和现有修复链，在中央线程登记基线与唯一回流目标后再写；不得猜默认分支就是当前产品源码。

必须使用独立clone/worktree、独立build目录和已打补丁SDK副本。尤其不要共享可写Flutter SDK、PUB_CACHE中的已修改依赖、native构建树或安装中的设备。任何旧工作树的未提交configure/脚本修改先清点和保存；不得reset --hard、git clean或覆盖来获得看似干净的基线，也不能不加说明地混入新包。

每个可恢复阶段及时commit/push，推送前核对远端、推送后回读。失败测试可以作为明确标记的草稿检查点保留，不能写成通过。提交应小而完整，带缺陷编号、原因及验证范围，不顺带全文件格式化、改名或重构。

设备agent可以将最新集成分支正常merge到自己分支，但不要改写已共享历史。CORE合入修复优先保留原提交的正常merge。不要同一修复既cherry-pick又merge；确需替代集成方式时，必须登记原SHA到集成SHA的映射。禁止force-push/历史回退和自动重试覆盖他人提交。

冲突不是仅选ours/theirs：由文件负责人比较接口和测试语义处理，设备agent重测受影响路径。跨仓修复合入前保存候选向量和依赖；各仓尚未完整集成时标为partial integration，不能宣布整包通过。

## 6. 如何既并行又始终使用最新修改源码

每轮候选包开始前，拉取并核对所有适用集成分支和已登记的设备修复分支，保存准确输入向量。测试包必须由这些最新适用源码构建，不能下载历史发布JAR/SO代替。FFmpeg必须包含已经完成的e8df200c修复；“版本号更新”不等于修复已经链接。

一次构建/安装/测试期间输入固定，不在进行中的构建目录git pull。固定的是刚取得的当前候选，不是回退或永久钉住历史代码。

CORE可以继续并行开发。若远端在测试中前进，实机结果仍是该明确向量的有效观察，但不得转写成最新HEAD验收：记录passed_for_vector与integration_retest_required。下一轮吸收新修改并重建；合入后的最新整合向量必须再测关键路径。

现有CI的新鲜度门保持，不因为并行就忽略失败或改写结果。最终联合验收约定短暂的集成分支稳定窗口；窗口内不向候选集成分支推送，双方新增成果保存到已登记的增量工作分支。长时间设备播放不应冻结全部开发。稳定窗口的开始/结束必须在中央线程声明，不能凭默认假定。

CORE维护按角色/缺陷隔离的CI并发分组，避免设备PR取消主线CI；DEVICE不得为触发CI安装源码写入workflow、移除校验或修改令牌权限。设备分支若不触发现有校验，报告给CORE接线，不把0次运行或skipped视为通过。

旧包只允许作为明确标注的对照样本，不计入本次候选验收。最终接受前保留完整源码来源和产物哈希核对；复用来源不明的旧对象、静态库或缓存属于未完成构建，不能冒充全量最新源码。

## 7. DEVICE开始阶段的具体顺序

### DEV-ENV：环境与成果清点

报告可访问的实体设备型号/API/ABI/固件、实际操作通道、构建工具链和源码根。列出九根工作区中实际可见的内容，不假定都可执行。不默认操作所有adb设备，不清App数据、刷固件、解锁、root或修改账户/签名设置；可能破坏现有状态的动作另行取得用户授权。

首先验证本地已有修复是否已push或已包含于任务分支，保存dirty差异。只读的旧main不代表任务代码缺失。

### DEV-BUILD：构建可追溯的完整当前候选

先生成源码/补丁清单，再重新编译native链和PiliPlusX测试包。将必要的本机patch/script变成可审查、可保存的输入；不要一开始大改wrapper，也不要仅重编译Dart然后沿用旧libmpv。

记录mpv、FFmpeg、libplacebo、helper、App、media-kit及适用SDK/依赖的实际仓库/ref/SHA/补丁哈希；保存命令、选项、工具链版本、完整链接输入、ELF Build ID或哈希、JAR/APK哈希。FFmpeg静态链接进libmpv时，靠链接清单和产物链证明，不能只看运行版本字符串或几个marker。

核对安装的APK和测试进程实际加载库来自本轮包，不混用旧安装、另一个ABI或另一渠道的包。签名/账户凭据不进入Git和公开日志。

### DEV-SMOKE：先基线，再复杂画面

先启动/普通SDR/查询不依赖Player/选源/首帧/退出，再测HDR10、HLG、P5、P8.4及缺失或冲突元数据。条件允许至少覆盖LG-H870DS、现代DV设备、普通SDR设备；缺设备就记录未测，不模拟成通过。

主场景显式开启allowExperimental=true，同时回归false。记录App选源与Session实际使用的policy，不能只打开一个lab define就认为整条链已开启。PiliPlusX既有默认仍false，本方案没有悄悄修改产品默认。

普通自动路由与strict-lock实验分开记录。锁定实验成功不能当作普通Session接线完成。首次最小复现优先固定本地可公开/自有测试素材，网络DASH集成另做；不要将带鉴权的URL、cookie或私有影片上传。

### DEV-DEVICE：优先验证的真实反例

1. P8.4 profile256设备正确选中decoder；P5-only/缺失profile设备不走错误原生DV；记录实际codec identity和native-DV活动信息。
2. LG不因声明DV就放行裸HLG HDR；P8.4走转换时验证真实完整YUV配方、owner和输出，而不只看策略名。
3. 尺寸/帧率/编码逐rendition过滤正常，不把unknown能力和unknown颜色语义混为一谈。被误挡的合法片源应补真实源事实或窄化分类规则，不能全局恢复猜测。
4. 失败降级不重复同一失败依赖；无独立正确路径时明确失败，不接受错误颜色或虚报verified。
5. 快速换源、seek/pause、全屏、前后台、Surface重建、open/dispose和多Session，检查owner/generation、旧回调、黑屏、泄漏及声音状态。
6. 真实播放的帧/颜色/亮度/音画同步/稳定性分开报告。提交帧率不等于呈现帧率；LG旧API缺失的呈现通道不得重复伪造调查结论。

LG已有精确固件/ABI匹配、YUV8精度和离屏/窗口/vendor metadata的多层契约必须保留。出现新的实机证据可以提出有范围的修改，但不借本轮重开10-bit目标，不把LG参数扩大到全Android，不绕过owner/ACK/私有ABI权限。自称HDR的截图/系统提示不是充分的端到端颜色证明。

## 8. 缺陷登记、通信与状态

GitHub上的media-kit PR#4是中央协作线程。两个会话不会自动共享本地上下文，也不会持续监听对方。各自开始一轮、编辑高冲突文件前、push/集成前和交接前，都主动读最新登记与PR差异。可将同一条紧急阻塞消息通过用户转发加速，但权威记录必须落在GitHub。

共享GitHub账户的作者名不能区分agent，因此评论、提交和记录必须带CORE/DEVICE角色及缺陷编号。

DEVICE首条接手评论应包含：角色/工作编号、设备与构建能力、各仓当前基线、已有dirty/额外patch、计划文件范围、分支/PR、请求的共享文件认领，以及首轮候选构建目标。无共享文件冲突的预留设备任务可以登记后进行；共享文件必须得到确认后写。CORE通过回复接受/缩小/转交范围。离线或超时不自动产生第二个所有者；重新分配前先核对已有分支和提交，并显式记录交接。

每个缺陷至少记录：

- 设备/API/固件/目标显示器、精确源码向量与APK/库哈希；
- 片源规格与指纹、有效policy/实验标志、复现步骤；
- 预期与实际、完整原始错误及route/decoder/output事实、脱敏证据路径；
- 负责agent、共享文件授权、增量PR/修复提交；
- 修复前复现、修复后测试、其他设备/SDR负向回归；
- 集成提交、整合后实机复测和仍未知的部分。

分别维护三个状态维度，不用单一done混淆：implementation（reported/claimed/pushed）、validation（not_run/failed/passed_for_vector/blocked）、integration（pending/merged/retest_required/accepted）。测试失败不把已经push的实现退回planned；合入也不自动意味着设备复测通过。

中央计划和汇总JSON由CORE单写；DEVICE可在独立的docs/plans/device-validation/MK-ROUTING-20261011/<case-id>/文件中保存小型脱敏报告/manifest，较大日志和包使用双方可访问的持久artifact位置。必须记录URL/ID、哈希和过期时间，需要保留的证据在到期前归档，不能只留临时目录或短期下载令牌。

## 9. 每个设备修复的闭环

登记与认领 → 当前源码构建并复现 → 最小修复和回归测试 → 及时commit/push到已登记设备分支 → 设备结果和PR → CORE审查并集成到现有任务分支 → 最新整合向量宿主CI/App构建 → DEVICE重新构建并复测受影响实机路径 → 中央台账记录最终证据。

修复至少交付能复现/验证的回归（能宿主化则加入自动测试；只能实机验证则提供脚本和明确断言），不能只交一个“屏幕看起来好了”的补丁。不要删除失败断言、改变source filter来逃避已知错误、关闭experimental作为完成实验场景的替代，或将unsupported静默改成success。

## 10. 可以直接交给 DEVICE agent 的启动指令

你负责MK-ROUTING-20261011的DEVICE工作线：基于已经提交的路由与App代码做完整最新源码构建、实体设备验证及最小缺陷修复，不重做总体方案和已实现功能。先从Goodwu/media-kit的routing/MK-ROUTING-20261011读取本文、v3计划、schema3中央台账、PR#4最新评论；再读PiliPlusX PR#1/App台账和FFmpeg PR#1。核对真实远端与工作区dirty，报告工具链/设备能力，不根据旧main推断功能缺失。

在media-kit PR#4发布带DEVICE角色的接手登记，使用每仓从当前任务分支派生且已登记的device/MK-ROUTING-20261011/<缺陷号>增量分支；只提交尚未修复的设备问题，PR合回对应任务分支。不得直接push集成分支，不force-push，不改中央汇总JSON，不重复实现2a5d87/98a349/e8df200等既有修复。公共Session/realizer/App controller等冲突范围先认领确认。

第一优先级是最新native全链路和PiliPlusX整包来源闭合，然后LG与现代DV设备的自动路由验证，主场景experimental=true并回归false，普通自动与锁定实验分别验收。固定本轮最新源码向量进行构建测试，不使用旧JAR/SO冒充新源码构建；记录所有源码/补丁/链接输入/APK与实际加载库哈希。每个可恢复阶段及时commit/push并回读，提交脱敏复现、最小回归和实机结果。CORE继续公共逻辑/CI并单点集成，合入后你必须重测最新组合。设备不可达、构建输入缺失或能力不可观测时如实标记，不编造通过。
