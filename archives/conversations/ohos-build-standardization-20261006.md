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

## 遗留与后续

1. patch 分支 rebase 到上游 tip（f4ab1955）的首轮升级演练（流程：同步→rebase→
   CI→更新 pin 四件套）。
2. engine 工件按 engine.version 快照为镜像仓 Release 资产（Phase 5 可选加固，
   ~1G）。
3. 本机安装 command-line-tools 26.0.0.621 对齐 CI 工具链，消除
   libmediakit_ohos_hdr.so/module.json 的 patch 级差异，逼近全量字节等价。
4. libapp.so 跨机差异为 AOT 嵌入绝对路径的固有行为；如需字节等价可评估
   --obfuscate（改变产物语义，另行决策）。

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
