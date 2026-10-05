# 分支归一与全量功能测试（2026-10-05）

## Current State

用户决策四项（2026-10-05）：①handoff 证据迁独立库；②授权推送（含删远端已合并分支）；③测试深度=本地全量+Android 实机；④stash 核对后清理。归一原则：**五条非 main 分支无一需要整体 merge**，全部按"摘取独有增量 + 删除分支"处理；代码冲突一律取 main 侧（main 为超集），文档双向手工融合。

### 分支处置结果

| 分支 | 处置 | 依据 |
| --- | --- | --- |
| `codex/macos-shared-hdr-fix`（252c5851） | 代码已在 main `75743f5c` 同源落地；摘取 conversation 文档 + TASKS r4 章节后删除本地分支 | 48 文件对照：43 blob 与 main 一致，`hdr_route.dart`/`video_texture.dart` main 侧叠加 LG/Native-DV 增量为超集（取分支侧会回退 `nativeDvUnavailable`/`vdLavcOptions`/`hwdecMediacodecCopy`/android_output_presentation 集成）；`hdr_output_transfer_api_test.dart` 锁定的是分支旧枚举顺序（main 已有意重排、库内无按 index 序列化消费，`.name` 是唯一消费方式），废弃不迁 |
| `codex/macos-completion-handoff`（0ecd4d9d） | 证据全量迁 `~/src/media-kit-experiments`（提交 b4f9538：`artifacts/macos-ppx-completion-20261003/` 596 文件约 110MB + `macos-ppx-completion-20261003.md` + `macos-wakeup-shutdown-20261003.md`，纯增量零覆盖）；会话与 TASKS 增量融合回 main 后删除本地分支 | main `5fcdd976` 已刻意删除 `archives/experiments/` 并迁独立库，整体 merge 会回灌 60 万行 |
| `origin/ci/windows-mpv-ab`（bcdc9515） | 摘取 `.github/workflows/windows-mpv-diagnosis.yml` + `tool/windows_mpv_com_repro.py` 两诊断文件进 main；分支内 `windows_mta.dart`/`real.dart` 与 main 仅差 dart format/主线增量（等效已在 main）；其 8 行证据草稿废弃（experiments 库已藏 43 行终版） | 核心修复已由 `fix/windows-mpv-com-lifetime`（PR #3）进入 main |
| `origin/fix/windows-mpv-com-lifetime`（de035dbc） | 已完全合并（`e07781a2`），零摘取，仅删远端 | `git rev-list main..branch` 为空 |
| `main` | 本地领先 origin 3 提交（5fcdd976/8de8a0c2/75743f5c），推送授权已获 | TASKS 曾记录"未授权推送"，本次用户明确授权 |

### Stash / worktree 清理

- drop `stash@{0}`（P5 PQ 早期探针，018df6cb）：`getSurfaceDataSpace` getter 已在 main；LYA 私有 ABI 探针被整改批次 C（`5b32ff32`）有意移除并以 `SurfaceDataSpaceExt` 可注入扩展点替代（探针迁测试 App）——apply 会撤销已审整改决策。
- drop 重复的 ohos guard stash（5f9bdd3e）：与保留项字节相同。
- **保留 1 条待用户定夺**：`stash@{0}`（现名）"ohos-emulator-20260906-blocked-remove-emulator-guard"——移除 `OhosVideoController.create` 的 `Utils.IsEmulator` guard（9 行）。main 仍有该 guard，内容未被覆盖；属未完成的模拟器实验（配合当时 OHOS 无实体机），apply 与否是新的产品行为决策，不擅自处置。
- `git worktree prune` 清理 `/private/tmp/mk-mergecommit`、`/private/tmp/mk-premerge`（游离 HEAD 均在 main 历史）；两个 codex worktree 随分支删除移除；`~/src/luna-ohos-e3` OHOS 工作树保留。

### 遗留测试失配修复（main 既有、与归一无关）

- `platform_view_entry_contract_test.dart:326`：PR #3（7578e290）把 `real.dart` 终止调用包进 `withWindowsMta(() => mpv.mpv_terminate_destroy(ctx))` 后契约测试未同步，stale 自 10-02；CI 默认门禁不跑 media_kit_video 全量套件故未暴露。修复：搜索串去掉尾部分号以匹配包装形式（定位意图不变）。
- `hdr_source_classifier_device_facts_test.dart:51`：`8de8a0c2` 把 P5 EL 从硬编码 false 改为 `dvElPresent` 容器事实（null=未知，"Native-DV eligibility must not infer single-layer structure from a missing container fact"）后测试未同步。修复：无容器事实时期望 `isNull`，并以 `dvElPresent: false` 通道保留 Mystery Box 单层设备锚点。
- `test/web/darwin_wakeup_callback_owner_smoke.dart` 的 `avoid_print`（75743f5c 引入）加 ignore，analyze 基线回到 18。

## 测试结果

### 2.1 静态与单元（归一后 main 工作区，2026-10-05）

| 套件 | 结果 | 基线对照 |
| --- | --- | --- |
| media_kit `dart test`（`LIBMPV_LIBRARY_PATH` 指向 CI dylib 0.6.5，native 测试真实执行） | **88 通过 / 15 跳过**，player 全套（open/seek/playlist/dispose/事件泵）对真实 libmpv 全绿 | Windows CI 基线 81+15；macOS 本地多出的 native 测试全部执行通过 |
| media_kit `wakeup_callback_owner_test`（环境门禁，对**精确候选** mpv be044572…，SHA 与 r1 记录一致；`DYLD_LIBRARY_PATH=shared-ci-prepared-inputs-r2/inputs/lib` 解依赖） | **7/7 通过**（约 5s，与当时 dart-flutter-results.json 记录的 7 项一致） | r4 已审切片的既定验证复现 |
| media_kit `dart analyze` | 4 条（既有，不增） | 基线 4 ✓ |
| media_kit_video `flutter test` | **423/423 全过**（修复 2 个 stale 后；套件已从 204 扩容至 424 项） | 204 时代基线已过时；当前全绿 |
| media_kit_video `flutter analyze` | 18 条（修复 avoid_print 后） | 基线 18 ✓ |
| media_kit_hdr_lab `flutter test` | **268/268 全过** | 基线 268 ✓ |
| media_kit_hdr_lab `flutter analyze` | 0 条 | 基线 0 ✓ |
| `:media_kit_android_dataspace_vendor:testDebugUnitTest`（JDK17） | BUILD SUCCESSFUL | CI 同款门禁 ✓ |
| `tool/verify_macos_shared_bridge.py`（r4 候选 frameworks） | **PASS**（target ABI/诊断门禁/epoch/清理） | 明确不验证像素/性能/显示 |
| 5 个 `test/native/*.swift`（按 swift-fixture-results.json 原命令复现、对当前树源码） | **5/5 PASS**（wakeup owner fixture 末行 `shutdown end owner=1 cleared=1`） | 源码与 r4 快照 diff 仅测试文件为超集演进 |

### 2.2 macOS 产品链（media_kit_test 本地播放观察 app）

`flutter build macos --debug -t lib/local_playback_diagnostic.dart` exit 0；`flutter run` 托管启动（DDS eval 驱动导航；System Events AX 窗口枚举被系统权限阻断，VM service 为替代驱动通道）：

- **实播**：测试页 07 自动打开容器内 4K60 素材，`open.completed` 123ms；状态快照推进（72→95），3840×2160、playing=true、buffering=false、零 error 事件。
- **帧消费诊断**：completed-render→flutter-copy 通道活跃，约 38-40 render/s、copy 间隔 p50 16.68ms（≈60fps）。
- **播放中销毁**（导航 unmount → player.dispose）：无崩溃，进程存活。
- **重入**：二次 open 72ms、第二段播放 position 推进至 34.6s+、4K60 正常。
- **有序退出**（Apple event quit → applicationShouldTerminate）：preTermination 屏障与 wakeup 排空完整执行——wakeup-shutdown JSONL 记录 `plugin.prepare.lookup(hit=1) → owner.prepare.called → owner.prepare.cleared`（此前三次非有序启动均无此序列），统一日志 `wakeup shutdown begin/end owner=1`；flutter run 正常 "Lost connection to device"。
- **崩溃核查**：DiagnosticReports 20:00 后零新增 media_kit/mpv .ips；日志零 render-context/SIGABRT/FATAL。
- 观察项（非失败）：有序退出时 owner 注册表 `handles=0/cleared=0`（机制已执行；句柄计数语义留给五场景人工验收线核对）。
- 证据边界：页面 07 的 resize/seek 按钮未驱动（AX 权限限制）；该路径由 media_kit_video 423 项（含 viewport/resize 套件）与 r4 轮 frame-pacing 证据覆盖，UI 级人工操作仍归五场景任务。

证据文件（experiments 库 `artifacts/branch-consolidation-20261005/`）：`media-kit-demo-initialization-27010.jsonl`（观察器全程）、`media-kit-flutter-consumption-27010-*.jsonl` ×2（两段播放帧消费）、`media-kit-wakeup-shutdown-27010.jsonl`（退出排空序列）。

### 2.3 Android LYA 回归轮（P5，bc2306）：通过

当前 main（b31cd49b）+ libs 钉定 JAR（v2026.012 发布链 c3bab5fc）构建 p5-sdr 包（APK faf8d588…），LYA 实机 240s 轮：命名 P5 fixture 命中打开（hint dolbyVision P5/EL false）、路由 metadataReshape→nativeHdr/PQ（platformView+gpu-next+mediacodec）、VIDEOPARAMS 3840×2160 dolbyvision/pq/sigPeak4.93、SF BT2020_PQ 层活跃、EOS eof-reached + AUTO_COMPLETED true、BACK 后 AUTO_PLAYER_DISPOSE completed、四截图 pixel-judge 全「正常画面」、render_failures=0、零 FATAL/SIGSEGV、恢复链完整（原包 2086/自动亮度/熄屏）。记录：experiments 库 `branch-consolidation-android-round-20261005.md`；完整证据本机 `~/src/media-kit-build/evidence/branch-consolidation-20261005/`。操作备注：前两次尝试早退（产物目录为文件名前缀非目录；USB 连接方式弹窗抢占焦点——EMUI SYSTEM_ALERT，取消并 force-stop 后通过）；matrix-round.sh 两处 grep 为旧日志格式（OPEN 已按 ANDROID_HDR_OPEN_BEGIN 命中，非失败）。

### 2.4 推送与 CI

- **push main**：`3e6be578..b31cd49b`（4 提交）；**4 条远端分支全部删除**（codex/macos-shared-hdr-fix、codex/macos-completion-handoff、ci/windows-mpv-ab、fix/windows-mpv-com-lifetime）——本地与远端分支终态均仅剩 `main`。
- **OHOS run 37309826002：success**（HAP 构建绿）。
- ci.yml：push run 37309825922 被 workflow_dispatch run 的 concurrency（cancel-in-progress）按预期顶替；**dispatch run 37309892420（run_package_tests=true，24 job 全矩阵+四平台 package tests）**：23/24 绿（OHOS 独立 run 亦 success），唯一失败 `macOS (optional libs)`——**75743f5c 既有缺口首次进 CI 暴露**：该提交为 media_kit_test AppDelegate 新增 `MediaKitVideoPlugin.prepareForEngineShutdown`/`recordWakeupShutdownDiagnostic` 调用，但 no-libs 变体走 podspec 的 stub 插件（`common/darwin/Classes/stub/MediaKitVideoPlugin.swift` 仅 register()），成员缺失编译失败（本地带 libs 构建走真插件故未暴露；此前三个本地提交从未过 CI）。**修复**：stub 补 `#if os(macOS)` 守卫的 no-op 对应成员（无 libs 时本无 libmpv wakeup owner 可排空），本地以 CI 同款流程复现验证（删 media_kit_libs_* 行 + 清 SPM ephemeral → `flutter build macos` exit 0）；iOS/Windows/Linux/Android optional-libs 均不受影响（iOS 已绿）。修复提交随本轮推送，最终 CI 结论见下。

## Archive Metadata

- date: 2026-10-05
- entry: branch-consolidation
- agent: ZCode
- project: media-kit
- submodule:
- language: zh-CN
- tags: [archive, git, branch-consolidation, testing]
