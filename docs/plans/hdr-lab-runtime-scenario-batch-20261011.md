# HDR lab「一次构建 + 运行时场景 + 批量测试」总体方案（v1）

- 日期：2026-10-11
- 作者：team-specialist（agent-team 困难判断角色，只读产出）；Lead 复查并入档
- 设计基线：media-kit main `d7619227`（设计期间工作区仅有 TASKS.md 既有未提交修改，设计未触碰）
- 状态：**口径已裁决（2026-10-11 用户）**——第 9 节 4 项均已裁决，可进入 WP0/WP1；裁决后修订：A3 扩展注销**留在构建期**，不纳入 WP1（第 2.4/3 节相应收缩）
- 关联：`docs/requirements/android-hdr-auto-output.md`（R4.2 报告契约、第 6 节成熟度表）；`archives/conversations/hdr-lab-runtime-scenario-batch-20261011.md`（执行会话）

## 0. Lead 复查结论（2026-10-11）

- 方案两处对既往口径的**纠偏已由 Lead 独立抽查证实**：
  1. 编译期开关规模为 **150 处调用 / 139 个不同 key / 6 个文件**（主实验页 126，main 7、globals 9、sources 5、backend 2、service probe 1）——此前"126 处、6 文件"是以主页面单文件数冒充总数，作废。
  2. **"开关仅存在于 lab"前提不成立**：生产库 `media_kit_video` 直接消费 5 个同名编译期开关——`MEDIA_KIT_ANDROID_CONVERT_SURFACE_TRANSFER`、`MEDIA_KIT_ANDROID_HDR_CONVERT_ROUTE_LOCK`、`MEDIA_KIT_ANDROID_SURFACETEXTURE_POC`（`hdr_strategy_realizer.dart:506-517`）、`MEDIA_KIT_ANDROID_HDR_SURFACE_FORMAT`（`hdr_video_session.dart:69`）、`MEDIA_KIT_ANDROID_HDR_REVIEW_TRACE`（`hdr_native_dv_review.dart:14`）。**"一次构建"必须按 build identity 划界**：普通场景/源片/hint/观察窗矩阵运行时化；build-bound PoC 变体仍须独立构建，除非另立 lab-only planner 适配工作包。
- 其余关键抽查通过：`tool/build-android-test.sh` 强制 `--local-source` 并自动注入场景 defines（WP1 必须同步改构建入口）；`HdrPlaybackBlocked` 正常 return 仅报告 error（batch 不能以 open 无异常判通过）；结果落盘须先写 app 私有目录再 adb 镜像（/data/local/tmp 可读≠可写）。
- 审核等级：本方案为设计提案，V0 Lead 复查通过；WP1/WP2 实施时按其内容分别走机械审核/独立实施审核。

## 1. 方案总览

1. **固定被测二进制 + 启动时冻结配置 + 不可变批清单 + 顺序执行器 + 独立外部看门狗**。
2. WP1 实现同一 APK 的运行时场景切换；WP2 实现正常情况下一次启动自动跑完整批。
3. 配置采用 **Intent 中的 base64url JSON 启动信封 + 按 run ID 隔离的 JSON 文件**，不自动读取遗留固定文件。
4. 场景仅存在于 lab；生产默认策略、成熟度表、生产 API 均不修改。
5. Batch 默认每个 case 创建新 Player/Session；同 Session 连续换源必须显式声明，不能默认为整个批复用一个播放器。
6. 结果先由 app 在现有可写位置原子持久化，再由 adb 流程汇集到 `/data/local/tmp` 批次目录。
7. 故障口径：Dart Timer 无法恢复整个进程/native 死锁；硬挂死继续整批需要外部自动重启，不能同时保证"绝不第二次启动"。

## 2. 架构与组件设计

### 2.1 已核实事实与边界

只读检查，未修改文件、未构建、未启动设备。

**A. 配置规模与已有行为**（调用数见第 0 节；迁移必须以 key、类型、默认值、消费点清单驱动，不能按"126 个独立开关"实施）：

- main 在初始化 MediaKit、方向、创建页面之前读取编译期配置，适合插入运行时冻结点（`media_kit_hdr_lab/lib/main.dart:14`）。
- `sources` 是可变列表；无本地源时会下载公开样片（`lib/common/sources/sources_native.dart:18`）。
- GATE_OPEN 当前优先于 PREFER_CONVERT 和 POLICY_EXPERIMENTAL；GATE_OPEN 只放开成熟度、保持默认策略顺序，A6 则把 P8.4 reshape 提到首位。迁移须保留此优先级（`lib/tests/01.single_player_single_video.dart:3073`）。
- 普通路径 R4.2 当前主要输出 `HDR_SESSION_REPORT/PREDICTION/CANDIDATE/ACTUAL` 日志；已有 HDR10 journal 提供结构化序列化先例（主页面 `:4021`、`lib/common/android_hdr_session_diagnostic.dart:76`）。

**B. 生产库耦合（必须披露）**：三个历史编译期开关被生产 realizer 消费、影响 transfer 准入与 route.hwdec，lab 实验 planner 又检查这些结果（`media_kit_video/lib/src/hdr/hdr_strategy_realizer.dart:233,506-517`；`lib/common/android_surface_texture_experiment.dart:84`）；另有生产 Session 的 `MEDIA_KIT_ANDROID_HDR_SURFACE_FORMAT`（`hdr_video_session.dart:69`）与 review trace 开关（`hdr_native_dv_review.dart:14`）。

边界：
1. 本任务不新增、不迁移运行时开关到生产库，不修改上述生产文件。
2. 这些配置标为 **build-bound**，与普通运行时 flags 白名单区分。
3. APK 的 build identity 保存实际编译值；运行时要求不匹配的值 → 明确拒绝，不允许"lab 日志显示开了，但生产 realizer 没变"。
4. 普通 A1/A3-no-HLG/A4/A5/A6、源路径和观察窗，可在同一二进制内切换。
5. 若要求历史 SurfaceTexture 强制 importer、PQ limited 等实验也全部运行时化，需另行批准 lab-only planner 适配设计；非机械替换，不纳入本方案默认承诺。

### 2.2 配置对象及冻结点

| 对象 | 内容 | 生命周期 |
|---|---|---|
| `LabBuildIdentity` | APK 构建标识、native candidate、build-bound 配置 | 随二进制固定 |
| `LabLaunchEnvelope` | schema、run ID、配置载体及 hash、恢复信息 | 每次进程启动一次 |
| `LabScenario` | 已补齐默认值的强类型场景配置 | 加载后不可变 |
| `LabBatchManifest` | 场景表、case 表、批级预算与结果规则 | 加载后不可变 |

加载顺序：`WidgetsFlutterBinding.ensureInitialized()` → Android 调 lab `LoadOnce` MethodChannel（非 Android 用原默认值）→ 读完整配置字节、核验 hash、解析 schema、校验类型和 key → 构造完整有效配置、深度冻结、发布只读 snapshot → 按有效配置执行 diagnostics、MediaKit 初始化、方向、source 准备、页面选择。**不在播放期间重新读 Intent 或配置文件。**

禁止使用"可修改的全局 currentScenario"切换 batch case：WP2 在加载时生成每个 case 的有效不可变 snapshot 逐个注入；进程级配置始终不变。

默认值原则：逐项保持原默认（含 `-1`/`0`/空串/`SURFACE_PRODUCER=true`/`DIAGNOSTICS=true`）；无启动配置 = 当前无 define 基线（公开样片下载等），不得把构建脚本 HDR 预设当默认；有配置但解析失败 → 明确 `CONFIG_REJECTED`，不静默回退；未知 key、错误类型、重复 JSON key、非法枚举、字符串布尔一律拒绝。

### 2.3 载体选型

| 方案 | 判断 |
|---|---|
| 全量 JSON 放 Intent | 仅用于小场景（shell 转义、Binder 长度限制） |
| 自动读取固定配置文件 | **不采用**（残留文件污染无配置启动、并行/恢复串批） |
| **Intent 信封 + 显式文件引用** | **推荐**：启动身份明确、支持大 manifest、文件可归档 |

启动信封 = 无换行 base64url JSON，内容二选一：`inlineScenario` 或 `configFile`+`configSha256`；不同时接受。输入目录 `/data/local/tmp/media-kit-hdr-lab/input/<runId>/manifest.json`，必须由 Intent 显式引用；无 extra 不读任何文件；读取后只用内存副本。初始工程预算：信封 ≤16 KiB、manifest ≤1 MiB，限制 case 数/嵌套深度/字符串长度（实现单测固定，非平台上限）。

### 2.4 MainActivity / MethodChannel

新增 lab-only `ScenarioChannel.kt`（通道 `media_kit_hdr_lab/scenario`，方法 `LoadOnce`）：Kotlin 负责 Intent/文件读取/大小限制/启动级缓存（后台线程，不阻塞 UI 线程；缓存属进程启动上下文）；Dart 负责完整 schema、默认值归一化、场景校验。注册先例 `CapabilitiesChannel.kt:21`。

必须处理现有 `singleTop`（`AndroidManifest.xml:9`）：`onNewIntent` 不允许热改运行中配置，不同 run ID 返回"需要冷启动"；runner 每次新 run 先 `am force-stop` 再 `am start -W`；Activity 重建读同一 frozen snapshot。

**A3 卸载扩展注销（2026-10-11 裁决：留在构建期，不纳入 WP1）**：现有 BuildConfig 编译期条件与注销时序（`MainActivity.kt:235`，`super.configureFlutterEngine` 后、早于任何 Session 创建）保持不变；A3 扩展注销场景继续按独立构建处理。日后若要运行时化，另立 lab Kotlin bootstrap 工作包再评估。

### 2.5 const 迁移及 admission

机械规则：
- 普通 `static const bool/int/String` → 指向已冻结场景的只读 getter 或显式初始化 `final`；**不**永久 `static final`（WP2 case-local 配置会被首个 case 锁死）；页面消费者用实例 getter 读 `widget.scenario`，进程级 helper 读进程 snapshot。
- `const bool.fromEnvironment(...)` 条件 → 普通布尔表达式；局部 `const` → `final`；`_convertExperiment`/`_surfaceTextureExperiment` 改实例 `late final`；与配置无关的 const（MethodChannel/Duration/Widget/literal Map）保持 const。

已确认 const 依赖点：两个实验对象构造（主页面 `:843`、`:852`）、backend derived enabled（`:28`、`:100`）、局部环境值（主页面 `:4873`、`:5536`；main `:16`、`:36`、`:53`）。**文本扫描不能替代 analyzer**——Worker 必须以 analyzer/编译确认无遗漏常量上下文，不得批量删 const 掩盖问题。

Admission 零语义变化：只替换取值来源，不改 OR 条件集合、`>0`/`>=0` 边界、固定源要求、分支优先级、抛错条件、one-open owner 语义。现有门禁：HDR10 `conflictingFlags`（:1139）、Native DV Session（:1359）、Native DV Release（:2788）、Convert/LG strict（:2947、:4566）。schema 校验是外围新门禁，不得借此简化原门禁；测试含"合法固定诊断 + 逐个冲突 flag"参数化拒绝矩阵。

### 2.6 Batch 执行器

新增 `LabBatchRunner` + 薄 `LabBatchScreen`，复用现有 Session 工厂、hint 生成、open 与 cleanup 逻辑，不复制 HDR 决策。状态机：`validate → preflight → mount → open → observe/actions → snapshot → cleanup → commit result → next`。

默认隔离：每 case 新 Player/Session/执行上下文；先挂载 `HdrVideo` 完成布局再 open（避免 Surface 绑定死锁）；前一 case cleanup 屏障完成才建下一个活跃 Session；不依赖 `State.dispose()`（不能 await）。现有 cleanup 语义复用但暴露可等待入口（主页面 `:5842`、`:5972`）；Session 不拥有调用方 Player，须分别 dispose（`hdr_video_session.dart:1135`）。

同 Session 连续换源：显式 `sameSessionSequence` case（P5→SDR→P8.4、mapper 状态恢复）；复用 auto-second-source 的 `session.open` 路径而非定时结构（主页面 `:5407`）；每次 open 独立 `openId`，Session generation 由库维护；LG single-open 实验拒绝此模式（`android_hdr_convert_experiment.dart:10`、`hdr_video_session.dart:356`）。

定时器与动作——现有计时基准不同，不能机械搬进循环：swap 从页面 `initState` 计时（:4724）、second-source 从首次 open 返回计时（:5407）、部分 pause 按媒体位置（:3510）。WP1 保持旧行为；WP2 动作 schema：`clock = caseStarted | openReturned | mediaPosition`，动作 `setPreference/setPolicy/seek/openNext`，记录 requested/started/completed/failed；runner 持可取消 Timer/订阅，回调捕获 `caseId+openId+executionEpoch`；开始下一 case 前取消并 drain。Batch v1 不支持任意 139 key 逐 case 覆盖：进程级（diagnostics/native 注销/探针/启动方向）、case 级（源/hint/GATE/POLICY/模拟/观察窗/受支持动作）、特殊独立场景（engine destroy、N1/N4、固定 journal、双视图——有适配器后再进 batch；不需重建但可能需另一次冷启动）。

成败判定：不能仅以 `session.open()` 无异常判通过——`HdrPlaybackBlocked` 写 error 报告后正常返回（`hdr_video_session.dart:434`）。至少检查：open 对应报告、`error/actual/verified`、源复核类、观察时长与播放进度、预期事件与候选跳过原因、cleanup 完成。`verified=true` 是 Session/解码配置校验，不等于颜色/亮度/可见画面通过。

### 2.7 失败、看门狗和结果落盘

两层超时：
- **层一 app 内软超时**：open/观察/动作/cleanup 分别设 deadline，单调时钟，按预期暂停/seek 调整"进度停滞"判断（硬 deadline 不暂停）。单片段失败：记录 → 有界清理 → 原子提交结果 → 继续。**`Future.timeout` 不取消底层 native 调用**；超时后确认 cleanup 完成才可同进程继续，否则标记进程不可继续。
- **层二 adb/host 独立看门狗**：监视 heartbeat/case deadline/进程存活；Dart/UI/native 全卡死也能写 host failure、有界收集诊断后 force-stop，用同 APK 同 manifest hash 从下一个未完成 case 恢复；新增 `attemptId/processInstanceId`，不把重启伪装成同一次执行；每 case 与全批恢复次数封顶。
- **推荐口径：正常批一次 app 启动；故障批一次 runner 命令，允许自动重启恢复**（开放问题 2）。

写盘路径（事实：可读 `/data/local/tmp` ≠ app 可写，DAC/SELinux 未实测）：
1. app 写 `getExternalStorageDirectory()` 下 `media-kit-hdr-lab/<runId>/<attemptId>/`：`events.jsonl`、每 case 结果、批次 checkpoint；临时文件 + flush + 同目录 rename 原子提交（现有先例 `android_hdr_session_diagnostic.dart:491`）。
2. host runner 在 case 完成后 adb shell 镜像到 `/data/local/tmp/media-kit-hdr-lab/results/<runId>/<attemptId>/`，最后 `adb pull` 归档。
3. 不以 release 包 `run-as` 为默认；设备不允许 shell 读取 app external files 时 preflight 停止并报告缺口，不静默退化为"只有 logcat"。

## 3. 文件级变更清单（拟议）

### WP1 运行时配置

| 文件 | 变更 |
|---|---|
| `lib/common/lab_scenario.dart`（新增） | 强类型配置、默认值、key 注册表、不可变 snapshot、scope 分类 |
| `lib/common/lab_scenario_loader.dart`（新增） | LoadOnce、hash、schema 解析、初始化屏障 |
| `lib/common/lab_build_identity.dart`（新增） | build-bound 配置与二进制声明；不冒充运行时可切换项 |
| `lib/main.dart` | 7 处替换；冻结点在 MediaKit/方向/source/page 之前 |
| `lib/common/globals.dart` | 9 处替换；snapshot ready 后生成初始 configuration，保留 ValueNotifier/UI 行为 |
| `lib/common/sources/sources_native.dart` | 5 处替换；本地源从 snapshot 初始化，保留无配置下载行为；不改 `MEDIA_KIT_TEST_CLIPS` OS 环境入口 |
| `lib/tests/01.single_player_single_video.dart` | 126 处迁移；实验对象取消配置 const 依赖；不改 admission 与动作语义 |
| `lib/common/sources/android_hdr_player_backend.dart` | 2 处迁移；derived enabled 改 getter；PoC 与 build-bound 一致性检查 |
| `lib/common/android_service_probe.dart` | enabled 迁移；保留 `kDebugMode && Platform.isAndroid` 门禁 |
| `android/.../ScenarioChannel.kt`（新增） | Intent/file 启动快照、LoadOnce（不含 A3 注销运行时化——已裁决留构建期） |
| `android/.../MainActivity.kt` | 注册 channel、处理新 Intent |
| `tool/build-android-test.sh` | 保留 ninja→JAR→Gradle 链；增加 runtime-lab 模式，不再强制源路径/注入场景 defines（现 `:34` 强制 `--local-source`、`:49-64` 注入 11 个 defines） |
| `media_kit_hdr_lab/tool/run_scenario.py`（新增） | 配置校验、编码、push、冷启动、日志及启动证据 |
| `media_kit_hdr_lab/test/` | 解析、defaults、const 迁移、admission 对照、启动冻结测试 |

### WP2 batch

| 文件 | 变更 |
|---|---|
| `lib/common/lab_batch_manifest.dart`（新增） | manifest、case snapshot、覆盖白名单、预期 schema |
| `lib/common/lab_batch_runner.dart`（新增） | 状态机、软看门狗、动作调度、恢复 checkpoint |
| `lib/common/lab_result_writer.dart`（新增） | 原子结果、JSONL journal、完整性标记 |
| `lib/common/lab_hdr_report_json.dart`（新增） | R4.2 完整序列化；借鉴现有 helper，不反解析日志字符串 |
| `lib/tests/01.single_player_single_video.dart` | 暴露窄 mount/open/report/awaited-cleanup 适配面；batch 禁止旧自动入口并行启动 |
| `lib/tests/lab_batch_screen.dart`（新增） | 当前 case、进度、取消入口；单一活跃视频上下文 |
| `lib/main.dart` | 显式 batch 分流，不改无配置分支 |
| `media_kit_hdr_lab/tool/run_batch.py`（新增） | host watchdog、恢复、镜像、pull、归档索引 |
| `media_kit_hdr_lab/tool/check_results.py`（新增） | schema/hash/条数/终态/预期判读 |
| `media_kit_hdr_lab/test/` | batch fake transport、超时、旧回调隔离、失败后继续与结果完整性测试 |

生产库与 PiliPlusX 文件不列入实施写入范围。

## 4. manifest / 结果 / 日志 schema 草案

### 4.1 Manifest（示例 hash 为占位）

```json
{
  "schemaVersion": 1,
  "batchId": "hdr-20261011-01",
  "requiredBuildIdentity": "candidate-id",
  "process": {
    "native": { "unregisterVendorExtension": false },
    "flags": { "MEDIA_KIT_DIAGNOSTICS": true }
  },
  "defaults": {
    "isolation": "freshPlayerSession",
    "openTimeoutMs": 30000,
    "cleanupTimeoutMs": 15000,
    "hardCaseTimeoutMs": 120000,
    "observation": { "clock": "openReturned", "durationMs": 60000, "endCondition": "window", "requirePlaybackProgress": true }
  },
  "scenarios": {
    "a3-no-hlg": { "flags": { "MEDIA_KIT_AUTO_SINGLE_PLAYER": true, "MEDIA_KIT_ANDROID_HDR_TRANSACTION": true, "MEDIA_KIT_ANDROID_HDR_GATE_OPEN": true, "MEDIA_KIT_ANDROID_HDR_SIMULATE_NO_HLG": true } },
    "a6-reshape": { "flags": { "MEDIA_KIT_AUTO_SINGLE_PLAYER": true, "MEDIA_KIT_ANDROID_HDR_TRANSACTION": true, "MEDIA_KIT_ANDROID_HDR_POLICY_EXPERIMENTAL": true } }
  },
  "cases": [
    {
      "caseId": "p84-a3",
      "scenario": "a3-no-hlg",
      "source": { "path": "/data/local/tmp/media-kit-p84-full.mp4", "sha256": "<64 hex>", "declaredClass": "dvP84", "identityEvidenceRef": "fixture-inventory-entry" },
      "hint": { "mode": "descriptor", "descriptor": { "codec": "hevc", "transfer": "hlg", "primaries": "bt.2020", "dynamicMetadata": "dolbyVision", "dvProfile": 8, "dvCompatibilityId": 4, "enhancementLayer": false } },
      "startMs": 0,
      "actions": [],
      "expected": { "sourceClass": "dvP84", "verified": true, "actualStrategy": "baseLayerConvert", "outputTransfer": "pq", "candidateSkips": [{ "strategy": "baseLayerDirect", "reason": "displayLacksTransfer" }], "visualAcceptance": "manual" }
    }
  ]
}
```

约定：`source.declaredClass` 是外部声明，不自动写成解码事实；`hint.mode` 至少 `legacyFixture/none/descriptor`（错误 hint 用 descriptor 表达）；`expected.sourceClass` 与 hint 独立（支持 A4）；batch 显式 hint 与旧 WRONG_HINT/NO_HINT 同现即拒绝；继承顺序固定：代码 defaults → manifest defaults → scenario → case 白名单覆盖，输出完整 effective snapshot；A3 例子的期待依赖设备能力（DV 设备 nativeDV 可能先命中），不能把历史 LYA 预期当通用断言；`window`/`eos`/`eosOrWindow` 分开，早到 EOS 是否通过由 manifest 明确决定。

### 4.2 每 case 结果

字段组：身份（schemaVersion/batchId/runId/attemptId/caseId/processInstanceId/sessionInstanceId/openId）、哈希（APK/build identity、manifestRawSha256、effectiveScenarioSha256、fixture claim/verification）、时间（UTC 起止、单调 elapsed、分段耗时）、终态（completed/openFailed/blocked/timeout/crashed/cleanupFailed/notRun）、断言（逐项 expected/observed）、R4.2（source/origin、prediction、全部 candidates、actual、dataspace、hwdecCurrent、verified、degradeReason、error、generation）、播放事实（位置/EOS/采样区间/丢帧计数/动作记录）、清理（session/Player dispose、controller retirement、未闭合项）、证据限制（visualAcceptance、panelAcceptance、缺失证据）、完整性（resultCommitted、事件 seq、丢弃/截断计数）。

R4.2 结构必须保留完整 route 字段（含 `offscreenTransfer`）、每个 candidate 的 maturity/feasible/skipReason/route、null 与 unavailable 原义、原有降级枚举值（契约 `docs/requirements/android-hdr-auto-output.md:162`）。`watchdogTimeout`/`manifestInvalid` 是 lab harness error，不塞进生产 `HdrDegradeReason`。

### 4.3 日志

强制证据不依赖可能被禁用的 `debugPrint`：单独 journal + 简短 marker。

```text
LAB_SCENARIO {"schemaVersion":1,"runId":"...","manifestSha256":"...","effectiveScenarioSha256":"...","configOrigin":"file"}
LAB_CASE_START {"caseId":"...","openId":"...","executionEpoch":1}
LAB_HDR_REPORT {"caseId":"...","openId":"...","sessionInstanceId":"...","generation":2,"report":{}}
LAB_CASE_END {"caseId":"...","executionStatus":"completed","assertionStatus":"pass","resultSha256":"..."}
LAB_BATCH_END {"planned":6,"terminal":6,"recoveredProcesses":0,"status":"completed"}
```

完整配置写 `scenario.effective.json`，`LAB_SCENARIO` 携带 hash 与来源；不把 139 个 key 塞进可能被 logcat 截断的单行；日志丢失不毁已提交的结构化结果，但须在证据清单标记缺失。

## 5. 证据协议变更

关联键从 `APK SHA ↔ define 集` 变为 **`APK SHA + build identity + manifest SHA + effective scenario SHA + run/attempt/case/open identity`**；APK SHA 只证明"运行了哪个二进制"，不再证明"本次运行了哪个场景"。

必须归档：①构建材料（APK SHA、安装后字节核验、Git HEAD/dirty patch/依赖锁、JAR/.so hash、build-bound 配置与构建日志）；②启动材料（manifest 原始字节及 SHA、解码信封、实际 adb 参数/serial/`am start -W` 输出、`LAB_SCENARIO` 与 effective snapshot、进程/实例 ID、启动 UTC）；③片源材料（fixture SHA/ffprobe 身份、push 后核验、声明/实测/未验证三态区分——LG 无 sha256sum 不以 MD5 偷换，MD5 仅辅助传输检查、host 保留 SHA）；④执行材料（reports/events、每 case 结果、cleanup、checkpoint、原始 logcat、SF/截图/视频、watchdog/restart 记录、用户颜色/亮度/流畅性独立记录）；⑤收尾材料（planned↔terminal 一一对应、notRun/interrupted/未评估项、文件清单与 hashes、电源/亮度恢复日志）。

宿主归档建议 `~/src/media-kit-build/evidence/hdr-lab-runtime/<runId>/`；正式实验记录仍入 `~/src/media-kit-experiments/`。不能只存 hash 不存原始配置；Reviewer 应能独立重算 hash、展开有效场景并复核判断。

## 6. 风险与缓解

| 风险 | 缓解与验证 |
|---|---|
| adb 双层 shell 引号/空格/Unicode | 信封 base64url 无换行；host 用参数数组调用 adb；专项测试 |
| Intent 太大 | 小信封引用文件；限大小，不依赖 Binder 极限 |
| 遗留配置串场景 | 无 extra 不读文件；每 run 独立目录；force-stop；禁动态 reload；hash 不符拒绝 |
| `/data/local/tmp` 不可读 | 目录遍历权限 + 文件 world-readable（0755/0644）；实际 app 打开测试，不以 shell 能读替代 |
| `/data/local/tmp` 不可写/SELinux | app 私有目录 journal + adb 镜像；不以 chmod 0777 作通用保证 |
| runtime 与生产编译期值不一致 | build-bound 清单、启动一致性检查；不匹配拒绝 |
| 场景代码不再 tree-shake | lab 包体积/AOT 增大属预期；测包大小/冷启动/默认播放；关闭分支不得启动 Timer/FFI/订阅 |
| 无配置 baseline 改变 | defaults golden + 无 extra 真机对照 |
| static final 锁住首个 case | case snapshot 显式注入；A→B→A 用例 |
| swap/second-source 晚回调污染下一片段 | Timer/订阅登记、epoch token、awaited cleanup；故意制造晚回调测试 |
| `open()` 成功但播放被阻断 | 同时检查 R4.2 error/actual/verified 和播放进度 |
| native 死锁致软 watchdog 失效 | host 独立 deadline、force-stop/恢复；故障运行新增 attempt |
| 超时后底层操作仍执行 | 不把 Future.timeout 当取消；cleanup 不明不复用进程 |
| 写盘失败/日志截断/断连 | 原子结果、seq/丢失计数、host checkpoint；基础设施错误不算通过；恢复次数封顶 |
| LG 激进休眠 | `svc power stayon true`，唤醒核验屏幕/keyguard；结束恢复原电源策略 |
| 热节流污染长批 | 起止记录温度/电量；冷却间隔、固定顺序；API24 无 thermal status 时标未知 |
| 能力诊断干扰 EGL | batch 不调用含 `eglInitialize/eglTerminate` 的全量 EGL inventory（`CapabilitiesChannel.kt:17` 有记载）；用库安全查询或独立进程盘点 |
| filename/hint 被误当事实 | fixture hash/ffprobe、hint、decoder class 三栏独立 |
| JSON 结果被误当视觉验收 | 自动结果只证明结构化断言；画质/面板呈现独立人工验收 |

## 7. 分期验收判据与工作量

**WP0 文档与基线冻结（先行，0.5–1 人日，不改生产代码）**：冻结 150 处调用/139 key 清单（type/default/scope/消费者/build-bound 分类）；冻结 baseline、A3/A6、固定诊断 admission 预期；确认开放问题。

**WP1 一次构建多场景冷启动（3–5 人日实施 + 1–2 人日独立复核/实机）**，验收：
1. 静态：六消费者不再直接读运行时场景 `fromEnvironment`；build identity 例外有 allowlist；139 key 默认值逐项一致；lab 全套测试/analyze；生产库与 PiliPlusX 零 diff。
2. 默认行为：无 extra 启动与旧无 define 基线一致；不自动进 batch/HDR；不受残留 manifest 影响。
3. 同包切场景：一个 APK SHA 依次默认 HDR/GATE/A6/no-HLG/wrong-no-hint/不同片源；每轮有效配置与 host hash 相符；A→B→无配置第三轮无残留。
4. 拒绝路径：malformed base64/错误类型/未知 key/文件缺失/hash 不符/非法组合均明确拒绝；固定诊断 admission 集合与迁移前一致。
5. 门禁回归：用仍 experimental 的格（如 P8.4 reshape）验证 GATE 区别，不用已 verified 的 HLG direct。
6. 构建入口：`tool/build-android-test.sh --runtime-lab` 走现有 ninja→JAR→Gradle 链，不散拼第二路构建。

**WP2 一次启动完整批次（5–8 人日实施 + 2–3 人日独立复核/故障验证）**，最低验收批：HDR10/P8.4/P5/SDR、同片不同 hint/策略、一项有效 seek/preference action、一项故意失败、失败后一个正常片段、一项 same-Session 换源（若声明支持）。判据：正常批仅一个 `am start`；N 个 case 恰好 N 个终态；单片段失败不阻断；软卡死可终止本项、硬挂死由 host watchdog 恢复剩余；恢复同 APK 同 manifest、attempt 清晰无重复终态；迟到回调不污染下一 case；结果镜像 pull 后 hash 一致；batch 结果与 WP1 单场景一致（性能比较控制热状态）；人工观察项不自动变 pass。

**仍需独立构建**：换 libmpv JAR/native 库；改 media-kit/lab 被测源码；不同 ABI/debug-release/原生编译选项；本次不改生产库条件下的 build-bound transfer/importer/surface-format 变体。普通场景/源片/hint/观察窗/GATE/A6/模拟能力变更**不需要重新构建**。

## 8. 文档先行清单

1. `docs/requirements/android-hdr-auto-output.md`：加 lab-only 运行时/批测附录；明确 R4.2 外层关联身份与结构化归档规则；明确 planning skip 与 runtime Degraded 区别；说明 Session verified 不替代视觉/面板验收。**不改生产门禁、R3 降级枚举、第 6 节成熟度表。**
2. `media_kit_hdr_lab/README.md`：从 dart-define 面改为 runtime 配置入口；schema、默认行为、优先级、冷启动要求；batch 支持场景表与必须独立启动场景表、build-bound 例外；输入权限、结果镜像、LG logcat/休眠、恢复及归档命令。
3. 六个消费者及实验 helper 注释：修正已不准确的 compile-time/no-op/tree-shake 表述；GATE 与 A6 区别、固定源限制保留。
4. `tool/build-android-test.sh`：usage、默认注入规则、runtime-lab 模式、构建身份与运行身份分离。
5. `archives/conversations/android-hdr-auto-output-20261002.md`：顶部新增当前执行协议入口；旧 obs APK/define 证据保留为历史。
6. `TASKS.md`：本任务验收与 context；关联既有"诊断日志落盘"任务避免重复建设；记录生产 define 耦合与裁决。

## 9. 开放问题（2026-10-11 用户裁决结果）

1. **生产库同名 define 的范围例外** → **接受划界**：本次"一包"限定同一 build identity；CONVERT_SURFACE_TRANSFER / CONVERT_ROUTE_LOCK / SURFACETEXTURE_POC / SURFACE_FORMAT / REVIEW_TRACE 为 build-bound，对应 PoC 场景保留独立构建。日后运行时化须另立 lab-only planner 适配工作包。
2. **硬挂死时的一次启动口径** → **接受**：正常批一次 app 启动；故障批一次 runner 命令，允许 host watchdog 自动重启恢复（attemptId/processInstanceId 显式记录，不伪装成同一次执行，恢复次数封顶）。
3. **结果写入主体** → **接受**：app 原子写 app-specific external 目录（`media-kit-hdr-lab/<runId>/<attemptId>/`），host 流程 adb 镜像到 `/data/local/tmp/media-kit-hdr-lab/results/` 再 pull 归档；设备不允许 shell 读取时 preflight 明确报缺。
4. **A3 卸载扩展是否纳入 WP1** → **不纳入**：注销条件留在构建期（BuildConfig），A3 扩展注销场景维持独立构建；运行时化留待日后单独评估。

建议项裁定：⑤ WP2 首版限定普通 Session 矩阵，engine-destroy/N1/N4/双视图/LG strict single-open 留独立场景适配——随裁决 1/4 的划界精神一并成立；⑥ 非 Android lab 旧 dart-define 工作流：runtime-lab 构建不得被旧 define 隐式覆盖，非 Android 平台暂保持原 define 工作流，不建兼容 loader（需要时另立）；⑦ 性能长批温度阈值/冷却时长/最长预算按设备基线逐设备定，不给通用承诺。
