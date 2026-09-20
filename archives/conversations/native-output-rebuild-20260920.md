# native output rebuild lifecycle

## Current State
- 背景: 当前分支包含 macOS native surface、OHOS HDR surface 和播放器释放路径的协同修改。
- 目标: 提交本轮代码及对应契约测试，保留未纳入范围的协作文档和本地产物。
- 当前状态: 跨平台生命周期修复与 macOS 首帧呈现 gating 已分别提交。
- 关键结论:
  - native output 重建、释放和跨平台入口变更属于同一代码切片。
  - 新增 3 个契约测试覆盖 OHOS 生命周期、候选渲染分支和 platform-view 入口隔离。
  - 本地产生的 `libs/ohos/.../libs/` 未纳入提交。
  - 协作引导文件未纳入提交；TASKS 与本归档仅用于满足仓库提交上下文要求。
- 下一步:
  - 真实 macOS/OHOS 设备验证 native output 生命周期。
- 接手入口:
  - 代码：`media_kit_video/lib/src/video_controller/`
  - 测试：`media_kit_video/test/`

## Session Log

- S1: 完成当前工作树检查、契约测试修正、静态检查和精确暂存。

## Findings

- F1: `git diff --check` 通过；Dart format 检查未产生格式改动。
- F2: 3 个契约测试通过；Dart 依赖解析仅有本地 `package:lints` 缺失提示。
- F3: macOS Metal blit 现在等待命令完成，并通过 output epoch 与首帧呈现状态决定 native output active。

## Decisions

- D1: 不使用 `--no-verify` 绕过提交钩子，补充最小任务与归档上下文。
  - 依据: 仓库钩子要求实质变更关联 TASKS 和 conversation archive。
  - 备选方案: 跳过钩子；影响是失去仓库约束检查。
  - 影响: 本归档与 TASKS 一并纳入本次提交。
- D2: 本轮只提交 macOS native output 相关的 7 个代码文件与 `.gitignore`，保留协作文档和 OHOS 本地产物。
  - 依据: 剩余 tracked 修改均集中于首帧呈现、输出 epoch 和控制器生命周期。
  - 备选方案: 纳入未跟踪二进制；影响是把本地构建产物混入代码提交。
  - 影响: 工作树仍保留未跟踪引导文件与 OHOS 二进制。

## Action Items

- [ ] A1: 在真实 macOS/OHOS 设备上完成 native output 生命周期验收。

## Archive Metadata
- date: 2026-09-20
- entry: native-output-rebuild
- agent: Codex
- project: media-kit
- submodule:
- language: zh-CN
- tags: [archive, native-output, hdr, ohos, macos]
