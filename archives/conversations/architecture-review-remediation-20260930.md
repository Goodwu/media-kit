# 架构审查整改（2026-09-30 起）

## Current State

- **任务**：按 `archives/reviews/goodwu-commits-architecture-review-20260930.md`（只读审查，P0×3 / P1×6 / P2×5）整改。整改按审查第 5 节投入产出顺序分批执行，每批独立提交。
- **批次进度**：
  - [x] 批次A（P2-3 止血）：OHOS 隔离入口 analyzer 排除（analysis_options.yaml 注明 CI 分工）、macos 契约测试缩进无关化修复、ci.yml 恢复 push→main 触发 package tests（手动分发保留按需开关）、ohos.yml 触发分支由已归档分支改为 main。验收：media_kit_video analyze 0 error（18 info/warning，与审查记录一致）、`flutter test` 全过（含先前加载失败的 macos 契约测试）。
  - [ ] 批次B（P1-4）：owner broker 按引擎分组 + media_kit 公开窄接口。
  - [ ] 批次C（P0-1/P1-5）：厂商私有回退改可注入扩展点；诊断探针移出库。
  - [ ] 批次D（P0-2）：Goodwu libmpv release 发布并设为默认下载源；lock/CHANGELOG 记录 mpv/FFmpeg/libplacebo commit；CI 校验 JAR 版本标识。
  - [ ] 批次E（P0-3）：HdrOutputPolicy 提炼进 media_kit_video + 单测矩阵。
  - [ ] 批次F（P1-1/P1-2）：SurfaceOwnerLedger 抽取 + NativeOutputOwner 统一生命周期。
  - [ ] 批次G（P1-3/P1-6）：公开配置 API 收敛；Darwin DisplayLink 驱动 + 异步完成通知。
  - [ ] 批次H（P2-2/P2-4）：硬编码路径改环境变量、.vscode 忽略、测试 App 拆分（诊断平台另立）。
- **授权边界**：`git filter-repo` 仓库瘦身（P2-1）审查明确需要单独授权，本次整改不执行；Git LFS/证据外置的仓库结构调整同样待用户确认方案后另行处理。
- **整改原则**：不改已实机验收过的行为语义（P0–P5 验收结论依赖当前行为）；重构以"行为等价 + 可单测化"为门槛；每批提交前跑 analyze/test 回归。

## 关键依据（历史区）

- 审查文档对 OHOS 文件的裁定：`platform_view_video_ohos.dart` 仅被契约测试以文本引用，编译发生在隔离 OHOS 构建（flutter_ohos fork SDK）；方案 B（analyzer 排除 + CI 分工）为审查认可的整改路径。共享入口不泄漏 OHOS API 由 `test/platform_view_entry_contract_test.dart` 守护。
- macos 契约测试失败根因：上游合并（`a886f556`）改变 `video_texture.dart` 嵌套缩进深度，测试第 29-34 行按精确缩进逐字符匹配 `if (nativeSurface && ...)` 断裂；组合顺序本身（候选挂载→Texture 回退→激活挂载，736/764/773 行）未变。
- ci.yml 原状：package tests 仅 `pull_request || inputs.run_package_tests`；上游基准为 `on: [push, pull_request]` 无条件运行。
