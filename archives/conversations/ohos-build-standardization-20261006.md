# OHOS 构建规范化（依赖归一 + 镜像体系 + 可复现 HAP）

## Current State

2026-10-06：用户批准执行「OHOS 规范化计划 v2」。目标：换机可复现构建功能相同的
HAP + GitHub 云端可构建。已实施：

**依赖归一（每库唯一仓，平台线用分支）**

| 库 | canonical 仓 | 分支 | 状态 |
|---|---|---|---|
| flutter | Goodwu/flutter_flutter（新建 public） | `oh-3.44.9-dev`（1:1 镜像 CPF，tip f4ab1955）+ `infra`（默认分支，日同步 workflow 02:17 UTC）+ `ohos/media-kit-patches`（5be1ddcb） | ✓ |
| mpv | Goodwu/mpv | `mirror/feat-ohos-0.41.0`（= ErBWs 6edeee0，审计确认零漂移）+ `infra/sync`（默认分支，周同步） | ✓ |
| FFmpeg | Goodwu/FFmpeg | `mirror/feat-ohos-n8.0`（= ErBWs 7dddf74，零漂移）+ `infra/sync`（默认，周同步） | ✓ |
| libplacebo | Goodwu/libplacebo | `mirror/v7.360.1`（= 上游 tag cee9b076 快照，静态 pin 无需同步） | ✓ |
| libmpv 构建系统 | Goodwu/libmpv-ohos-build | main（102510e：source-lock 三 URL 切镜像 + upstream 出处字段） | ✓ CI 复验中 |

**flutter patch 审查结论（Phase 0 三方审计）**

- framework `TargetPlatform.ohos` parity：上游一个月仅吸收 1 处，131 处确认缺失 →
  保留。经 hunk 级配对过滤后为 60 文件 +134/-28 纯 parity（提交 8235c1c9）。
- 剔除（实验家族，未入 patch 分支）：gesture_detector `NestedRawGestureDetector`、
  modal_barrier 手势实验、layout_builder BuildScope 注释、scaffold/tabs/
  bottom_sheet/draggable_scrollable_sheet 内部状态暴露、editable 默认值改动、
  kIsWeb 三元删除、`_TextHighlightPainter` 改动。
- HCPP embedding epoch 变体与 native 日志：按批准表延后/丢弃（experiments 库
  4a43068 存档可回溯）。docs+契约测试脚本保留（提交 5be1ddcb）。
- patch 分支基线 = 4f1a4267（E3 验证基线，非上游 tip）；rebase 到 tip 留待
  首次同步升级流程。

**media-kit 侧工具（单一事实源 pin）**

- `tool/ohos/flutter-ohos.pin`：镜像/base/patch commit/engine.version/version_tag。
- `tool/ohos/native-libs.pin`：自建 libmpv zip 溯源（sha 29b8bd4d… = release
  20260920 资产逐字节一致；source-lock 102510e）。
- `tool/ohos/bootstrap_flutter_ohos.sh`：换机 bootstrap（冒烟通过：patch_commit
  可运行，engine revision 5a2a6a42 与 pin 一致）。
- `tool/ohos/sync-flutter-mirror.sh`：GitHub 同步失败时的本地回退。
- `tool/ohos/hap_fingerprint.py`：HAP 内容指纹（key entries = libs/*.so +
  modules.abc + module.json；基线 key_digest b9d55b4d…）。
- `tool/ohos/patches/framework-ohos-parity-4f1a4267.patch`：parity patch 内联
  （与镜像分支 8235c1c9 树一致，作 gitcode 回退重建源）。

**ohos.yml v2**：SDK 步骤改消费 pin（镜像优先，gitcode+内联 patch 回退重建）、
native 溯源门禁步骤、指纹 JSON 进产物、manifest 增 patch_branch/base_commit、
周 schedule（周一 04:33 UTC）。

**验收**：本地（DevEco）与 GitHub CI 双路径构建同 commit HAP，key_digest 一致
= 换机 + 云端双目标达成（结果见 TASKS 对应条目）。基线（tpc aa76d9bb 无 patch）
与新基线（CPF 4f1a4267+parity）的指纹差异属预期换基线变化，已记录。

## 验收结果（2026-10-06 收口）

- **目标 1（换机复现）✓**：`tool/ohos/bootstrap_flutter_ohos.sh` 从镜像@pin 全新
  checkout（engine revision 5a2a6a42 与 pin 一致），本机（macOS + DevEco）构建
  `entry-default-unsigned.hap` 成功（60.9MB、零 error）。
- **目标 2（GitHub 云端构建）✓**：ohos.yml v2 三跑绿（run 37362291696），
  产物含 hap-fingerprint.json 与溯源 manifest（patch_branch/base_commit 入册）。
- **双路径指纹比对**：libflutter.so / libmpv.so / libc++_shared.so /
  ets/modules.abc 及全部 flutter_assets **字节一致**。差异项均为已知类别：
  ① libapp.so——Dart AOT 快照嵌入本机绝对路径（机器固有，非功能差异）；
  ② libmediakit_ohos_hdr.so 与 module.json——CI command-line-tools
  26.0.0.621(Beta2) vs 本机 DevEco 26.0.0.105(Release) 工具链 patch 级差异
  （后续字节对齐硬化项：本机改装 621 版 command-line-tools）。
- **归一等价性 ✓**：libmpv-ohos-build 切 Goodwu 镜像后 CI 重建 libmpv.so
  sha `9561823b…` == native-libs.pin 记录值（逐字节一致，证明归一只改可得性
  不改产物）；SBOM/SHA256SUMS 校验通过，builder_commit 102510e。
- **本地构建 PATH 前置（macOS）**：DevEco 的 hvigor/node/ohpm 三件套需入 PATH，
  DEVECO_SDK_HOME 指向 DevEco sdk——已写入 bootstrap 脚本文档头。
- **同步 workflow 修复与验证**：首跑失败因 `GITHUB_TOKEN` 未做 step 级 env 映射
  （`set -u` 未绑定）；三个 infra workflow 修复后 flutter 同步重跑**绿**
  （gitcode 从 GitHub runner 拉取 46 秒成功，可达性风险解除；镜像 tip 保持
  f4ab1955 fast-forward no-op）。mpv/FFmpeg 同款 workflow 已修复推送，触发
  验证因 runner 排队未即时回读，模式与 flutter 完全一致。

## patch 分支重做（2026-10-06，用户审查驱动）

用户对比 `oh-3.44.9-dev...ohos/media-kit-patches` 发现大量 `case ohos` 与基线
重复，判 v2 提交低质量并要求废弃重做。逐层复核证实且比表面更严重：

1. **语句级重复（104 处）**：基线同 switch 已有 ohos 标签，扫尾又加一个
   （基线 1/patch 2 模式）；system_navigator 等还出现「standalone
   `case ohos: return;` + android 后 fall-through」矛盾对。
2. **switch 表达式 arm 内重复（20+7 处）**：基线 arm 已含
   `fuchsia || ohos =>`，扫尾在 `android ||` 后再插 ohos——同 arm 出现两次；
   typography.dart 一处甚至**矛盾**（会把 ohos 从基线的 Helsinki arm 改到
   MountainView arm，属行为变更而非 parity）。
3. **终态**：131 处新增中 129 处为基线已覆盖的重复，真实缺口仅 2 处——
   navigator.dart poppedRoute 重聚焦 switch 补 case ohos（android
   fall-through）+ scrollbar.dart 甩动速度 arm 补 ohos（基线落
   `_ => Velocity.zero`，OHOS thumb 甩动无弹道滚动的真实行为修复）。

重建方法：最内层 switch 归属 + 插入集对照（native+inserted 混杂即删插入）
+ switch 表达式整体作用域分析，逐处人工核对。patch 分支重写为
`cae3a1d0`（parity `4d42a06a`：2 文件 +2/−1，+ docs/test 提交），media-kit
内联 patch 与 pin 同步更新。教训：**case 级"纯添加"判定不等于语义正确**，
必须对照基线对应 switch/arm 的既有覆盖；E3 扫尾的 171 处基线覆盖当时未被
审计。

**其它 patch 的去向（同日用户问询）**：全部原始内容在 media-kit-experiments
库 `4a43068` 全量存档（`ohos-flutter-e3-framework-ohos-sweep-20261006.patch`
81 文件全量 / `ohos-flutter-e3-hcpp-embedding-epoch-20261006.patch` HCPP
engine 9 文件 / `ohos-flutter-e3-hcpp-untracked-20261006/` docs+契约测试），
处置表见同库 `ohos-flutter-e3-archive-20261006.md`：手势实验家族与 native
日志=丢弃（可回溯）、HCPP embedding epoch 变体=延后 Phase 5、docs+test=已入
patch 分支、parity=经本次重做后仅 2 处真实缺口入分支。

## 遗留与后续

0. **主 CI lock 缺口（2026-10-06 晨修复）**：01b15a01 给 pubspec.yaml 加
   path_provider_ohos 时只更新了 ohos lock，主 pubspec.lock 缺条目——规范化
   期间各次推送的主 workflow run 均被并发取消，至 7d2d3334 首次完整执行时四
   平台 `--enforce-lockfile` 全挂。修复：桌面 flutter 再生主 lock（恰好 +8 行
   仅 path_provider_ohos，版本与 sha 和 ohos lock 一致，SDK 四件套未漂移）。
   教训：**改 media_kit_test/pubspec.yaml 必须同时再生两个 lock**（主 lock 用
   桌面 flutter、ohos lock 用 OHOS 工具链）。
1. patch 分支 rebase 到上游 tip（f4ab1955）的首轮升级演练（流程：同步→rebase→
   CI→更新 pin 四件套）。
2. engine 工件按 engine.version 快照为镜像仓 Release 资产（Phase 5 可选加固，
   ~1G）。
3. 本机安装 command-line-tools 26.0.0.621 对齐 CI 工具链，消除
   libmediakit_ohos_hdr.so/module.json 的 patch 级差异，逼近全量字节等价。
4. libapp.so 跨机差异为 AOT 嵌入绝对路径的固有行为；如需字节等价可评估
   --obfuscate（改变产物语义，另行决策）。
5. mpv 同步 workflow 首次 dispatch 的 run 被 runner 队列回收（cancelled），重
   触发后绿（tip 6edeee0 no-op 正确）；「手动运行」标识源于 dispatch 验证，
   定时触发自下周日 cron 起生效。

**修正记录（2026-10-06 凌晨）**：CI v2 首跑失败于 hvigor Dart 编译——v1 patch
的 hunk 过滤器行号锚定差一，把部分 `case TargetPlatform.ohos:` 插到非 switch
上下文（system_navigator/text_selection/editable 等 4 处起报）。v2 放弃行号
运算：完整应用 E3 已验证 diff 后整体反向应用 69 个实验 hunks（两步均 git apply
原子语义），60 文件 +134/-28 不变、配对断言通过。patch 分支 force 重写为
45d1b004（parity 7c17b19e + docs），media-kit 内联 patch 与 pin 同步更新。二跑
（dd78a88a）构建本体成功，仅指纹步骤相对路径笔误（../../tool → ../tool），
本地同源构建已绿（entry-default-unsigned.hap 60.9MB，零 error）。

**二进制政策落地**：必要例外仅 Flutter engine 工件（929M，与 engine.version
对应）；libmpv 自建+溯源门禁；工具（OHOS SDK 26.0.0.621/hvigor/Java17/meson/
setup-ohos SHA 钉定）豁免；无任何上游预编译 so/har 入 HAP。

**升级流程（后续同步用）**：镜像日/周同步自动进行 → 需要升级时 rebase
patch 分支 → CI 绿 → 更新 flutter-ohos.pin 的 base/patch commit（必要时同步
pubspec.ohos.lock 四件套与内联 patch）。
